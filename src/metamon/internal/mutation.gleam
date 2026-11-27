//// Runs the mutants of a project, records the results and compares them with
//// a baseline. See `metamon/mutation` for the commands.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import metamon/internal/mutant.{type Mutant}
import simplifile

const results_path: String = "build/mutation/results.json"

const baseline_path: String = "doc/mutation/baseline.json"

const document_path: String = "doc/testing.md"

const start_marker: String = "<!-- mutation:start -->"

const end_marker: String = "<!-- mutation:end -->"

const work_root: String = "build/mutation/work"

/// A survivor is run this many more times before it counts, because property
/// tests draw a new seed on each run.
const retries: Int = 2

pub type Command {
  Run(workers: Int, exclude: List(String), files: List(String))
  ListMutants(exclude: List(String), files: List(String))
  Gate
  Baseline
  DocCheck
}

pub type MutationError {
  FileFailed(path: String, reason: simplifile.FileError)
  ParseFailed(path: String)
  ResultsUnreadable(path: String)
  NoTimeoutCommand
  UnmutatedTestsFail(output: String)
  BaselineNeedsFullRun
}

pub type Status {
  Killed
  Lived
  TimedOut
  CompileError
}

pub type Row {
  Row(
    file: String,
    line: Int,
    column: Int,
    function: String,
    mutator: String,
    text: String,
    status: Status,
  )
}

pub type Results {
  Results(files: List(String), excluded: List(String), rows: List(Row))
}

pub type Summary {
  Summary(killed: Int, lived: Int, timed_out: Int, compile_error: Int)
}

pub const usage: String =
  "usage: gleam run -m metamon/mutation -- COMMAND

  run [--workers N] [--exclude FILE]... [FILE]...
      Mutate the given modules, or every module under src/, and write
      build/mutation/results.json.
  list [--exclude FILE]... [FILE]...
      Print the mutants without running them.
  gate
      Fail when a mutant lives that doc/mutation/baseline.json does not list.
  baseline
      Record build/mutation/results.json as the baseline and rewrite the table
      between <!-- mutation:start --> and <!-- mutation:end --> in
      doc/testing.md.
  doc-check
      Fail when the table in doc/testing.md does not match the baseline."

/// Reads the command line. `Error(Nil)` means the usage should be printed.
pub fn parse_arguments(arguments: List(String)) -> Result(Command, Nil) {
  case arguments {
    ["run", ..rest] -> {
      use #(workers, exclude, files) <- result.map(
        parse_options(rest, 4, [], []),
      )
      Run(workers:, exclude:, files:)
    }
    ["list", ..rest] -> {
      use #(_, exclude, files) <- result.map(parse_options(rest, 1, [], []))
      ListMutants(exclude:, files:)
    }
    ["gate"] -> Ok(Gate)
    ["baseline"] -> Ok(Baseline)
    ["doc-check"] -> Ok(DocCheck)
    _ -> Error(Nil)
  }
}

fn parse_options(
  arguments: List(String),
  workers: Int,
  exclude: List(String),
  files: List(String),
) -> Result(#(Int, List(String), List(String)), Nil) {
  case arguments {
    [] -> Ok(#(workers, list.reverse(exclude), list.reverse(files)))
    ["--workers", count, ..rest] ->
      case int.parse(count) {
        Ok(count) if count > 0 -> parse_options(rest, count, exclude, files)
        _ -> Error(Nil)
      }
    ["--exclude", file, ..rest] ->
      parse_options(rest, workers, [file, ..exclude], files)
    ["--" <> _, ..] -> Error(Nil)
    [file, ..rest] -> parse_options(rest, workers, exclude, [file, ..files])
  }
}

/// Runs `command` and returns the exit code.
pub fn execute(command: Command) -> Result(Int, MutationError) {
  case command {
    Run(workers:, exclude:, files:) -> run(workers, exclude, files)
    ListMutants(exclude:, files:) -> list_mutants(exclude, files)
    Gate -> gate()
    Baseline -> record_baseline()
    DocCheck -> doc_check()
  }
}

pub fn describe(error: MutationError) -> String {
  case error {
    FileFailed(path:, reason:) ->
      path <> ": " <> simplifile.describe_error(reason)
    ParseFailed(path:) -> path <> ": glance cannot parse this module"
    ResultsUnreadable(path:) -> path <> ": not a mutation results file"
    NoTimeoutCommand ->
      "neither timeout nor gtimeout is on PATH (install GNU coreutils)"
    UnmutatedTestsFail(output:) ->
      "the tests fail before any mutation:\n" <> output
    BaselineNeedsFullRun ->
      "the baseline needs a run over every module: run without FILE arguments"
  }
}

// Choosing modules -----------------------------------------------------------

/// The modules to mutate, sorted: `files` when any are given, otherwise
/// every Gleam module in `all`, never one in `exclude`.
pub fn select_modules(
  all all: List(String),
  exclude exclude: List(String),
  files files: List(String),
) -> List(String) {
  let candidates = case files {
    [] -> list.filter(all, string.ends_with(_, ".gleam"))
    _ -> files
  }
  candidates
  |> list.filter(fn(file) { !list.contains(exclude, file) })
  |> list.unique
  |> list.sort(string.compare)
}

fn source_files() -> Result(List(String), MutationError) {
  simplifile.get_files("src") |> result.map_error(FileFailed("src", _))
}

fn chosen_files(
  exclude: List(String),
  files: List(String),
) -> Result(List(String), MutationError) {
  case files {
    [] -> source_files()
    _ -> Ok([])
  }
  |> result.map(select_modules(all: _, exclude:, files:))
}

fn read_sources(
  files: List(String),
) -> Result(Dict(String, String), MutationError) {
  list.try_map(files, fn(file) {
    simplifile.read(file)
    |> result.map(fn(source) { #(file, source) })
    |> result.map_error(FileFailed(file, _))
  })
  |> result.map(dict.from_list)
}

fn find_mutants(
  sources: Dict(String, String),
) -> Result(List(Mutant), MutationError) {
  dict.to_list(sources)
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> list.try_map(fn(pair) {
    mutant.find(file: pair.0, source: pair.1)
    |> result.replace_error(ParseFailed(pair.0))
  })
  |> result.map(list.flatten)
}

fn list_mutants(
  exclude: List(String),
  files: List(String),
) -> Result(Int, MutationError) {
  use files <- result.try(chosen_files(exclude, files))
  use sources <- result.try(read_sources(files))
  use mutants <- result.map(find_mutants(sources))
  list.each(mutants, fn(mutant) {
    io.println(
      mutant.file
      <> ":"
      <> int.to_string(mutant.line)
      <> " "
      <> mutant.function
      <> " "
      <> mutant.mutator
      <> " | "
      <> mutant.text,
    )
  })
  0
}

// Running mutants ------------------------------------------------------------

fn run(
  workers: Int,
  exclude: List(String),
  files: List(String),
) -> Result(Int, MutationError) {
  use files <- result.try(chosen_files(exclude, files))
  use sources <- result.try(read_sources(files))
  use mutants <- result.try(find_mutants(sources))
  use timeout_command <- result.try(find_timeout())
  io.println(
    int.to_string(list.length(mutants))
    <> " mutants in "
    <> int.to_string(list.length(files))
    <> " modules",
  )
  // Copies left behind by an interrupted run.
  let _stale = simplifile.delete(work_root)
  use projects <- result.try(
    int.range(from: 0, to: workers, with: [], run: fn(acc, index) {
      [work_root <> "/w" <> int.to_string(index), ..acc]
    })
    |> list.reverse
    |> list.try_map(fn(project) {
      copy_project(project) |> result.replace(project)
    }),
  )
  use timeout <- result.try(measure_unmutated(projects, timeout_command))
  use rows <- result.try(
    list.index_map(projects, fn(project, worker) { #(worker, project) })
    |> parallel_map(fn(pair) {
      let #(worker, project) = pair
      share(mutants, of: workers, for: worker)
      |> list.try_map(run_mutant(project, _, sources, timeout_command, timeout))
    })
    |> result.all
    |> result.map(fn(rows) { list.flatten(rows) |> sort_rows }),
  )
  // Only build output: a copy that cannot be removed is overwritten next run.
  let _cleaned = simplifile.delete(work_root)
  use _ <- result.map(write_results(Results(files:, excluded: exclude, rows:)))
  io.println(summary_line(rows))
  0
}

/// Runs the tests once without a mutation and returns the timeout for each
/// mutant: four times as long as the clean run, and at least a minute.
fn measure_unmutated(
  projects: List(String),
  timeout_command: String,
) -> Result(Int, MutationError) {
  case projects {
    [] -> Ok(60)
    [first, ..] -> {
      let started = monotonic_milliseconds()
      let #(status, output) = test_in(first, timeout_command, 900)
      let elapsed = monotonic_milliseconds() - started
      case status {
        Lived -> Ok(mutant_timeout(elapsed))
        _ -> Error(UnmutatedTestsFail(output:))
      }
    }
  }
}

/// The items worker `worker` of `workers` runs: every `workers`-th item,
/// starting at `worker`.
pub fn share(items: List(a), of workers: Int, for worker: Int) -> List(a) {
  items
  |> list.index_map(fn(item, index) { #(index, item) })
  |> list.filter(fn(entry) { entry.0 % workers == worker })
  |> list.map(fn(entry) { entry.1 })
}

/// Seconds a mutant may run: four times the clean run, at least a minute.
pub fn mutant_timeout(clean_run_milliseconds: Int) -> Int {
  int.max(60, clean_run_milliseconds * 4 / 1000)
}

fn find_timeout() -> Result(String, MutationError) {
  ["timeout", "gtimeout"]
  |> list.find(fn(name) { find_executable(name) |> result.is_ok })
  |> result.replace_error(NoTimeoutCommand)
}

/// Copies the project into `destination`, with the compiled dependencies so
/// that each copy only recompiles the mutated module.
fn copy_project(destination: String) -> Result(Nil, MutationError) {
  use _ <- result.try(
    simplifile.create_directory_all(destination <> "/build")
    |> result.map_error(FileFailed(destination, _)),
  )
  use entries <- result.try(
    simplifile.read_directory(".") |> result.map_error(FileFailed(".", _)),
  )
  copied_entries(entries)
  |> list.map(fn(entry) { #(entry, destination <> "/" <> entry) })
  |> list.append([
    #("build/packages", destination <> "/build/packages"),
    #("build/dev", destination <> "/build/dev"),
  ])
  |> list.try_each(fn(pair) { copy_entry(pair.0, pair.1) })
}

/// The top-level entries a copy of the project gets. The build directory is
/// copied separately, without the earlier mutation runs.
pub fn copied_entries(entries: List(String)) -> List(String) {
  list.filter(entries, fn(entry) {
    !list.contains(["build", ".git", "node_modules"], entry)
  })
}

fn copy_entry(source: String, target: String) -> Result(Nil, MutationError) {
  let copied = case simplifile.is_directory(source) {
    Ok(True) -> simplifile.copy_directory(source, target)
    Ok(False) -> simplifile.copy_file(source, target)
    Error(reason) -> Error(reason)
  }
  case copied {
    Ok(Nil) -> Ok(Nil)
    // build/dev is missing until the project has been built once.
    Error(simplifile.Enoent) -> Ok(Nil)
    Error(reason) -> Error(FileFailed(source, reason))
  }
}

fn run_mutant(
  project: String,
  mutant: Mutant,
  sources: Dict(String, String),
  timeout_command: String,
  timeout: Int,
) -> Result(Row, MutationError) {
  let path = project <> "/" <> mutant.file
  let applied = {
    use original <- result.try(dict.get(sources, mutant.file))
    use mutated <- result.map(mutant.apply(source: original, mutant:))
    #(original, mutated)
  }
  // A copy whose module cannot be written or restored would run every later
  // mutant of this worker against the wrong source, so the run stops.
  use status <- result.map(case applied {
    Error(Nil) -> Ok(CompileError)
    Ok(#(original, mutated)) -> {
      use _ <- result.try(write_file(path, mutated))
      let status =
        retry_while_lived(retries, fn(_) {
          test_in(project, timeout_command, timeout).0
        })
      use _ <- result.map(write_file(path, original))
      status
    }
  })
  io.println(
    status_name(status)
    <> " "
    <> mutant.file
    <> ":"
    <> int.to_string(mutant.line)
    <> " "
    <> mutant.mutator,
  )
  Row(
    file: mutant.file,
    line: mutant.line,
    column: mutant.column,
    function: mutant.function,
    mutator: mutant.mutator,
    text: mutant.text,
    status:,
  )
}

/// Runs `attempt` (with the attempt number, from 0) until a mutant does not
/// live, at most `retries` more times.
pub fn retry_while_lived(retries: Int, attempt: fn(Int) -> Status) -> Status {
  retry_from(0, retries, attempt)
}

fn retry_from(number: Int, retries: Int, attempt: fn(Int) -> Status) -> Status {
  case attempt(number) {
    Lived if number < retries -> retry_from(number + 1, retries, attempt)
    status -> status
  }
}

fn test_in(
  project: String,
  timeout_command: String,
  timeout: Int,
) -> #(Status, String) {
  let arguments = [
    "--kill-after=10",
    int.to_string(timeout),
    "gleam",
    "test",
    "--target",
    "erlang",
  ]
  case run_command(timeout_command, arguments, project) {
    Ok(#(0, output)) -> #(Lived, output)
    Ok(#(124, output)) | Ok(#(137, output)) -> #(TimedOut, output)
    Ok(#(_, output)) -> #(classify_failure(output), output)
    Error(Nil) -> #(CompileError, "")
  }
}

/// A failed `gleam test` that never ran a test did not compile.
pub fn classify_failure(output: String) -> Status {
  case
    string.contains(output, "error: ") && !string.contains(output, " passed")
  {
    True -> CompileError
    False -> Killed
  }
}

pub fn sort_rows(rows: List(Row)) -> List(Row) {
  list.sort(rows, fn(left, right) {
    string.compare(left.file, right.file)
    |> order_then(int.compare(left.line, right.line))
    |> order_then(int.compare(left.column, right.column))
    |> order_then(string.compare(left.mutator, right.mutator))
  })
}

fn order_then(first: order.Order, second: order.Order) -> order.Order {
  case first {
    order.Eq -> second
    _ -> first
  }
}

// Results --------------------------------------------------------------------

fn status_name(status: Status) -> String {
  case status {
    Killed -> "KILLED"
    Lived -> "LIVED"
    TimedOut -> "TIMED_OUT"
    CompileError -> "COMPILE_ERROR"
  }
}

fn row_to_json(row: Row) -> json.Json {
  json.object([
    #("file", json.string(row.file)),
    #("line", json.int(row.line)),
    #("column", json.int(row.column)),
    #("function", json.string(row.function)),
    #("mutator", json.string(row.mutator)),
    #("text", json.string(row.text)),
    #("status", json.string(status_name(row.status))),
  ])
}

fn row_decoder() -> decode.Decoder(Row) {
  use file <- decode.field("file", decode.string)
  use line <- decode.field("line", decode.int)
  use column <- decode.field("column", decode.int)
  use function <- decode.field("function", decode.string)
  use mutator <- decode.field("mutator", decode.string)
  use text <- decode.field("text", decode.string)
  use status <- decode.field("status", status_decoder())
  decode.success(Row(file:, line:, column:, function:, mutator:, text:, status:))
}

fn status_decoder() -> decode.Decoder(Status) {
  use name <- decode.then(decode.string)
  case name {
    "KILLED" -> decode.success(Killed)
    "LIVED" -> decode.success(Lived)
    "TIMED_OUT" -> decode.success(TimedOut)
    "COMPILE_ERROR" -> decode.success(CompileError)
    _ -> decode.failure(Killed, "mutant status")
  }
}

/// One mutant per line keeps the baseline diff readable. Each row is
/// serialised on its own, so a line of source holding `},{` stays intact.
pub fn results_to_json(results: Results) -> String {
  "{\"files\":"
  <> json.to_string(json.array(results.files, json.string))
  <> ",\"excluded\":"
  <> json.to_string(json.array(results.excluded, json.string))
  <> ",\"mutants\":[\n"
  <> string.join(
    list.map(results.rows, fn(row) { json.to_string(row_to_json(row)) }),
    ",\n",
  )
  <> "\n]}\n"
}

pub fn results_from_json(text: String) -> Result(Results, Nil) {
  let decoder = {
    use files <- decode.field("files", decode.list(decode.string))
    use excluded <- decode.optional_field(
      "excluded",
      [],
      decode.list(decode.string),
    )
    use rows <- decode.field("mutants", decode.list(row_decoder()))
    decode.success(Results(files:, excluded:, rows:))
  }
  json.parse(text, decoder) |> result.replace_error(Nil)
}

fn read_results(path: String) -> Result(Results, MutationError) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(FileFailed(path, _)),
  )
  results_from_json(text) |> result.replace_error(ResultsUnreadable(path))
}

fn write_results(results: Results) -> Result(Nil, MutationError) {
  write_file(results_path, results_to_json(results))
}

fn write_file(path: String, contents: String) -> Result(Nil, MutationError) {
  let directory =
    string.split(path, "/")
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  use _ <- result.try(
    simplifile.create_directory_all(directory)
    |> result.map_error(FileFailed(directory, _)),
  )
  simplifile.write(path, contents) |> result.map_error(FileFailed(path, _))
}

pub fn summarise(rows: List(Row)) -> Summary {
  let count = fn(status) { list.count(rows, fn(row) { row.status == status }) }
  Summary(
    killed: count(Killed),
    lived: count(Lived),
    timed_out: count(TimedOut),
    compile_error: count(CompileError),
  )
}

/// (killed + timed out) / (killed + timed out + lived), to a tenth of a
/// percent. A timed-out mutant counts as killed: the change made a test hang.
/// Mutants that did not compile are left out.
pub fn score(summary: Summary) -> String {
  let detected = summary.killed + summary.timed_out
  case detected + summary.lived {
    0 -> "100.0%"
    executed -> {
      let tenths = { detected * 1000 + executed / 2 } / executed
      int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10) <> "%"
    }
  }
}

fn summary_line(rows: List(Row)) -> String {
  let summary = summarise(rows)
  "score "
  <> score(summary)
  <> ": "
  <> int.to_string(summary.killed)
  <> " killed, "
  <> int.to_string(summary.lived)
  <> " lived, "
  <> int.to_string(summary.timed_out)
  <> " timed out, "
  <> int.to_string(summary.compile_error)
  <> " did not compile"
}

// Gate and baseline ----------------------------------------------------------

fn key(row: Row) -> #(String, String, String, String, Int) {
  #(row.file, row.function, row.mutator, row.text, row.column)
}

/// Survivors in `results` that `baseline` does not list. A survivor is
/// matched by module, function, mutator, line text and column, not by line
/// number, so moving code does not make it new.
pub fn new_survivors(baseline: List(Row), results: List(Row)) -> List(Row) {
  let known =
    baseline
    |> list.filter(fn(row) { row.status == Lived })
    |> list.map(key)
    |> set.from_list
  list.filter(results, fn(row) {
    row.status == Lived && !set.contains(known, key(row))
  })
}

fn gate() -> Result(Int, MutationError) {
  use baseline <- result.try(read_results(baseline_path))
  use results <- result.map(read_results(results_path))
  let new = new_survivors(baseline.rows, results.rows)
  list.each(new, fn(row) {
    io.println(
      "new survivor "
      <> row.file
      <> ":"
      <> int.to_string(row.line)
      <> " in "
      <> row.function
      <> ": "
      <> row.mutator
      <> "\n    "
      <> row.text,
    )
  })
  case new {
    [] -> {
      io.println(
        "no new survivors among "
        <> int.to_string(list.length(results.rows))
        <> " mutants",
      )
      0
    }
    _ -> {
      io.println(
        int.to_string(list.length(new))
        <> " mutants live that the baseline does not list. Add a test that kills them, or record them with `gleam run -m metamon/mutation -- baseline` and say why.",
      )
      1
    }
  }
}

/// Whether `results` mutated every module in `all` that it did not exclude.
pub fn is_full_run(results: Results, all: List(String)) -> Bool {
  results.files == select_modules(all:, exclude: results.excluded, files: [])
}

fn record_baseline() -> Result(Int, MutationError) {
  use results <- result.try(read_results(results_path))
  use all <- result.try(source_files())
  case is_full_run(results, all) {
    False -> Error(BaselineNeedsFullRun)
    True -> {
      use _ <- result.try(write_file(baseline_path, results_to_json(results)))
      use _ <- result.map(update_document(results.rows))
      0
    }
  }
}

/// Rewrites the table in doc/testing.md. A project without the file or the
/// markers keeps only the JSON baseline.
fn update_document(rows: List(Row)) -> Result(Nil, MutationError) {
  case simplifile.read(document_path) {
    Error(_) -> Ok(Nil)
    Ok(text) ->
      case render_document(text, rows) {
        Ok(rendered) -> write_file(document_path, rendered)
        Error(Nil) -> Ok(Nil)
      }
  }
}

fn doc_check() -> Result(Int, MutationError) {
  use baseline <- result.map(read_results(baseline_path))
  let current = simplifile.read(document_path)
  case current {
    Error(_) -> 0
    Ok(text) ->
      case document_matches(text, baseline.rows) {
        True -> 0
        False -> {
          io.println(
            document_path
            <> " does not match "
            <> baseline_path
            <> "; run `gleam run -m metamon/mutation -- baseline`",
          )
          1
        }
      }
  }
}

/// Whether the table in `text` shows `rows`. A text without the markers has
/// no table to compare.
pub fn document_matches(text: String, rows: List(Row)) -> Bool {
  case render_document(text, rows) {
    Ok(rendered) -> rendered == text
    Error(Nil) -> True
  }
}

/// The table of killed, lived and timed-out mutants per module.
pub fn table(rows: List(Row)) -> String {
  let modules =
    list.map(rows, fn(row) { row.file })
    |> list.unique
    |> list.sort(string.compare)
  let line = fn(name, rows) {
    let summary = summarise(rows)
    "| "
    <> name
    <> " | "
    <> int.to_string(summary.killed)
    <> " | "
    <> int.to_string(summary.lived)
    <> " | "
    <> int.to_string(summary.timed_out)
    <> " | "
    <> score(summary)
    <> " |"
  }
  [
    "| Module | Killed | Lived | Timed out | Score |",
    "|---|---:|---:|---:|---:|",
    ..list.map(modules, fn(module) {
      let name =
        module
        |> string.replace("src/", "")
        |> string.replace(".gleam", "")
      line(
        "`" <> name <> "`",
        list.filter(rows, fn(row) { row.file == module }),
      )
    })
  ]
  |> list.append([line("all", rows)])
  |> string.join("\n")
}

/// `text` with the table between the markers replaced. `Error(Nil)` when the
/// markers are missing.
pub fn render_document(text: String, rows: List(Row)) -> Result(String, Nil) {
  use #(head, rest) <- result.try(string.split_once(text, start_marker))
  use #(_, tail) <- result.map(string.split_once(rest, end_marker))
  head <> start_marker <> "\n" <> table(rows) <> "\n" <> end_marker <> tail
}

// FFI ------------------------------------------------------------------------

/// Runs every item in its own Erlang process. Other targets run them in turn.
@external(erlang, "metamon_ffi", "parallel_map")
fn parallel_map(items: List(a), fun: fn(a) -> b) -> List(b) {
  list.map(items, fun)
}

@external(erlang, "metamon_ffi", "monotonic_milliseconds")
@external(javascript, "../../metamon_ffi.mjs", "monotonic_milliseconds")
fn monotonic_milliseconds() -> Int

@external(erlang, "metamon_ffi", "find_executable")
@external(javascript, "../../metamon_ffi.mjs", "find_executable")
fn find_executable(name: String) -> Result(String, Nil)

/// The exit status and the combined stdout and stderr of a command.
@external(erlang, "metamon_ffi", "run_command")
@external(javascript, "../../metamon_ffi.mjs", "run_command")
fn run_command(
  executable: String,
  arguments: List(String),
  directory: String,
) -> Result(#(Int, String), Nil)
