//// Runs the mutants of a project, records the results and compares them with
//// a baseline. See `metamon/mutation` for the commands.

import glance
import gleam/bit_array
import gleam/bool
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

const counts_path: String = "build/coverage/counts.tsv"

const lcov_path: String = "build/coverage/lcov.info"

/// Where `metamon_e2e:prepare/0` writes the compiled modules, the escript
/// and the counts of every run of the escript.
const e2e_path: String = "build/coverage/e2e"

/// The variable that gives an end-to-end suite the path of the escript.
const e2e_variable: String = "METAMON_COVERAGE_ESCRIPT"

const erlang_build: String = "build/dev/erlang"

/// A survivor is run this many more times before it counts, because property
/// tests draw a new seed on each run.
const retries: Int = 2

/// Emulator flags for each test run: a process that grows past 256 MiB,
/// counting its binaries, is killed. A mutant can make a test allocate without
/// end, and several such runs in parallel fill the memory of a CI runner
/// before the timeout ends them. A process that recurses without end grows
/// to about 13 times the limit before the kill, so a larger limit lets one
/// test run take several gigabytes.
const test_emulator_flags: String = "+hmax 33554432 +hmaxib true"

pub type Command {
  Run(workers: Int, exclude: List(String), files: List(String), shard: Shard)
  ListMutants(exclude: List(String), files: List(String), shard: Shard)
  Merge(paths: List(String))
  Gate
  Baseline
  DocCheck
  /// Measure the tests, and each end-to-end command in `e2e` too.
  Coverage(e2e: List(String))
}

/// The mutants a run covers, so that CI can split a long run over several
/// jobs.
pub type Shard {
  /// Every mutant of the chosen modules.
  Whole
  /// Part `index` of `count`, both counted from 1: every `count`-th mutant,
  /// starting at the `index`-th, so each part gets a share of every module.
  Part(index: Int, count: Int)
}

pub type MutationError {
  FailedToReadFile(path: String, reason: simplifile.FileError)
  FailedToWriteFile(path: String, reason: simplifile.FileError)
  FailedToCopyProject(path: String, reason: simplifile.FileError)
  FailedToParseModule(path: String)
  NotAResultsFile(path: String)
  CannotMerge(reason: MergeError)
  TimeoutCommandMissing
  ErlMissing
  CoverageNeedsNewerGleam(version: String)
  NoPackageName
  CoverageBuildFailed
  CoverageFailed(status: Int)
  E2ePrepareFailed(status: Int)
  UnmutatedTestsFailed(output: String)
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
  Results(
    files: List(String),
    excluded: List(String),
    shard: Shard,
    rows: List(Row),
  )
}

pub type Summary {
  Summary(killed: Int, lived: Int, timed_out: Int, compile_error: Int)
}

pub const usage: String =
  "usage: gleam run -m metamon/mutation -- COMMAND

  run [--workers N] [--shard K/N] [--exclude FILE]... [FILE]...
      Mutate the given modules, or every module under src/, and write
      build/mutation/results.json. With --shard K/N, run only part K of N.
  list [--shard K/N] [--exclude FILE]... [FILE]...
      Print the mutants without running them.
  merge FILE...
      Join the results files of every part of a sharded run into
      build/mutation/results.json.
  gate
      Fail when a mutant lives that doc/mutation/baseline.json does not list.
  baseline
      Record build/mutation/results.json as the baseline and rewrite the table
      between <!-- mutation:start --> and <!-- mutation:end --> in
      doc/testing.md.
  doc-check
      Fail when the table in doc/testing.md does not match the baseline.
  coverage [--e2e COMMAND]...
      Run the tests with every module under src/ measured and write the
      lines they reach to build/coverage/lcov.info. Each --e2e COMMAND runs
      in sh with METAMON_COVERAGE_ESCRIPT set to an escript that runs the
      program with its lines counted, and its lines are added to those of
      the tests."

/// Reads the command line. `Error(Nil)` means the usage should be printed.
pub fn parse_arguments(arguments: List(String)) -> Result(Command, Nil) {
  case arguments {
    ["run", ..rest] -> {
      use options <- result.map(parse_options(rest, default_options(4)))
      Run(
        workers: options.workers,
        exclude: options.exclude,
        files: options.files,
        shard: options.shard,
      )
    }
    ["list", ..rest] -> {
      use options <- result.map(parse_options(rest, default_options(1)))
      ListMutants(
        exclude: options.exclude,
        files: options.files,
        shard: options.shard,
      )
    }
    ["merge", first, ..rest] -> Ok(Merge(paths: [first, ..rest]))
    ["gate"] -> Ok(Gate)
    ["baseline"] -> Ok(Baseline)
    ["doc-check"] -> Ok(DocCheck)
    ["coverage", ..rest] -> parse_e2e(rest, [])
    _ -> Error(Nil)
  }
}

fn parse_e2e(
  arguments: List(String),
  commands: List(String),
) -> Result(Command, Nil) {
  case arguments {
    [] -> Ok(Coverage(e2e: list.reverse(commands)))
    ["--e2e", "--" <> _, ..] -> Error(Nil)
    ["--e2e", command, ..rest] -> parse_e2e(rest, [command, ..commands])
    _ -> Error(Nil)
  }
}

type Options {
  Options(
    workers: Int,
    exclude: List(String),
    files: List(String),
    shard: Shard,
  )
}

fn default_options(workers: Int) -> Options {
  Options(workers:, exclude: [], files: [], shard: Whole)
}

fn parse_options(
  arguments: List(String),
  options: Options,
) -> Result(Options, Nil) {
  case arguments {
    [] ->
      Ok(
        Options(
          ..options,
          exclude: list.reverse(options.exclude),
          files: list.reverse(options.files),
        ),
      )
    ["--workers", count, ..rest] ->
      case int.parse(count) {
        Ok(count) if count > 0 ->
          parse_options(rest, Options(..options, workers: count))
        _ -> Error(Nil)
      }
    ["--shard", part, ..rest] -> {
      use shard <- result.try(parse_shard(part))
      parse_options(rest, Options(..options, shard:))
    }
    ["--exclude", file, ..rest] ->
      parse_options(
        rest,
        Options(..options, exclude: [file, ..options.exclude]),
      )
    ["--" <> _, ..] -> Error(Nil)
    [file, ..rest] ->
      parse_options(rest, Options(..options, files: [file, ..options.files]))
  }
}

/// Reads `K/N` with 1 <= K <= N.
fn parse_shard(text: String) -> Result(Shard, Nil) {
  use #(index, count) <- result.try(string.split_once(text, "/"))
  use index <- result.try(int.parse(index))
  use count <- result.try(int.parse(count))
  case 1 <= index && index <= count {
    True -> Ok(Part(index:, count:))
    False -> Error(Nil)
  }
}

fn shard_to_string(shard: Shard) -> String {
  case shard {
    Whole -> "whole"
    Part(index:, count:) -> int.to_string(index) <> "/" <> int.to_string(count)
  }
}

/// Runs `command` and returns the exit code.
pub fn execute(command: Command) -> Result(Int, MutationError) {
  case command {
    Run(workers:, exclude:, files:, shard:) ->
      run(workers, exclude, files, shard)
    ListMutants(exclude:, files:, shard:) -> list_mutants(exclude, files, shard)
    Merge(paths:) -> merge(paths)
    Gate -> gate()
    Baseline -> record_baseline()
    DocCheck -> doc_check()
    Coverage(e2e:) -> coverage(e2e)
  }
}

pub fn describe(error: MutationError) -> String {
  case error {
    FailedToReadFile(path:, reason:) ->
      "cannot read " <> path <> ": " <> simplifile.describe_error(reason)
    FailedToWriteFile(path:, reason:) ->
      "cannot write " <> path <> ": " <> simplifile.describe_error(reason)
    FailedToCopyProject(path:, reason:) ->
      "cannot copy " <> path <> ": " <> simplifile.describe_error(reason)
    FailedToParseModule(path:) -> path <> ": glance cannot parse this module"
    NotAResultsFile(path:) -> path <> ": not a mutation results file"
    CannotMerge(reason:) ->
      "cannot merge the results: " <> describe_merge_error(reason)
    TimeoutCommandMissing ->
      "neither timeout nor gtimeout is on PATH (install GNU coreutils)"
    ErlMissing -> "erl is not on PATH: coverage runs on the Erlang target"
    CoverageNeedsNewerGleam(version:) ->
      "coverage needs Gleam 1.19 or later, the first to keep the line numbers of the Gleam source in the BEAM files; gleam --version printed: "
      <> version
    NoPackageName -> "gleam.toml has no name line"
    CoverageBuildFailed ->
      "gleam build --target erlang failed, so there was nothing to measure"
    CoverageFailed(status:) ->
      "measuring the coverage failed (erl exited with "
      <> int.to_string(status)
      <> "); build/coverage/lcov.info was left as it was"
    E2ePrepareFailed(status:) ->
      "compiling the modules for --e2e failed (erl exited with "
      <> int.to_string(status)
      <> "); build/coverage/lcov.info was left as it was"
    UnmutatedTestsFailed(output:) ->
      "the tests fail before any mutation:\n" <> output
    BaselineNeedsFullRun ->
      "the baseline needs a run over every module: run without FILE arguments and --shard, or merge every part of a sharded run"
  }
}

fn describe_merge_error(error: MergeError) -> String {
  case error {
    NoResults -> "no results files"
    DifferentRuns -> "the files were made from different modules or exclusions"
    NotSharded -> "a results file is not from a sharded run"
    PartsMissingOrRepeated(count:) ->
      "every part from 1 to " <> int.to_string(count) <> " must appear once"
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
  simplifile.get_files("src") |> result.map_error(FailedToReadFile("src", _))
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
    |> result.map_error(FailedToReadFile(file, _))
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
    |> result.replace_error(FailedToParseModule(pair.0))
  })
  |> result.map(list.flatten)
}

/// The chosen modules, their sources and the mutants of `shard` in them.
fn mutants_to_run(
  exclude: List(String),
  files: List(String),
  shard: Shard,
) -> Result(#(List(String), Dict(String, String), List(Mutant)), MutationError) {
  use files <- result.try(chosen_files(exclude, files))
  use sources <- result.try(read_sources(files))
  use mutants <- result.map(find_mutants(sources))
  #(files, sources, select_shard(mutants, shard))
}

fn list_mutants(
  exclude: List(String),
  files: List(String),
  shard: Shard,
) -> Result(Int, MutationError) {
  use #(_, _, mutants) <- result.map(mutants_to_run(exclude, files, shard))
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
  shard: Shard,
) -> Result(Int, MutationError) {
  use #(files, sources, mutants) <- result.try(mutants_to_run(
    exclude,
    files,
    shard,
  ))
  use timeout_command <- result.try(find_timeout())
  io.println(
    int.to_string(list.length(mutants))
    <> " mutants in "
    <> int.to_string(list.length(files))
    <> " modules"
    <> case shard {
      Whole -> ""
      Part(..) -> ", part " <> shard_to_string(shard)
    },
  )
  // Copies left behind by an interrupted run.
  use _ <- result.try(delete_if_present(work_root))
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
  use _ <- result.try(delete_if_present(work_root))
  use _ <- result.map(
    write_results(Results(files:, excluded: exclude, shard:, rows:)),
  )
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
        Killed | TimedOut | CompileError -> Error(UnmutatedTestsFailed(output:))
      }
    }
  }
}

/// The mutants `shard` covers.
pub fn select_shard(mutants: List(a), shard: Shard) -> List(a) {
  case shard {
    Whole -> mutants
    Part(index:, count:) -> share(mutants, of: count, for: index - 1)
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

fn delete_if_present(path: String) -> Result(Nil, MutationError) {
  case simplifile.delete(path) {
    Ok(Nil) | Error(simplifile.Enoent) -> Ok(Nil)
    Error(reason) -> Error(FailedToWriteFile(path, reason))
  }
}

fn find_timeout() -> Result(String, MutationError) {
  ["timeout", "gtimeout"]
  |> list.find(fn(name) { find_executable(name) |> result.is_ok })
  |> result.replace_error(TimeoutCommandMissing)
}

/// Copies the project into `destination`, with the compiled dependencies so
/// that each copy only recompiles the mutated module.
fn copy_project(destination: String) -> Result(Nil, MutationError) {
  use _ <- result.try(
    simplifile.create_directory_all(destination <> "/build")
    |> result.map_error(FailedToCopyProject(destination, _)),
  )
  use entries <- result.try(
    simplifile.read_directory(".")
    |> result.map_error(FailedToReadFile(".", _)),
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
    Error(reason) -> Error(FailedToCopyProject(source, reason))
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

/// Compiles the project, then runs its tests with `test_emulator_flags`. The
/// compile comes first because the flags would also reach the Erlang compiler,
/// which needs more than the limit for a large module; the test run then finds
/// everything compiled.
fn test_in(
  project: String,
  timeout_command: String,
  timeout: Int,
) -> #(Status, String) {
  let flags = case getenv("ERL_ZFLAGS") {
    Ok(flags) -> flags <> " " <> test_emulator_flags
    Error(Nil) -> test_emulator_flags
  }
  case gleam_in(project, "build", timeout_command, timeout, []) {
    Ok(#(0, _)) ->
      case
        gleam_in(project, "test", timeout_command, timeout, [
          #("ERL_ZFLAGS", flags),
        ])
      {
        Ok(#(0, output)) -> #(Lived, output)
        Ok(#(124, output)) | Ok(#(137, output)) -> #(TimedOut, output)
        Ok(#(_, output)) -> #(classify_failure(output), output)
        Error(Nil) -> #(CompileError, "")
      }
    Ok(#(124, output)) | Ok(#(137, output)) -> #(TimedOut, output)
    Ok(#(_, output)) -> #(CompileError, output)
    Error(Nil) -> #(CompileError, "")
  }
}

/// Runs `gleam <command> --target erlang` in `project`, stopped after
/// `timeout` seconds.
fn gleam_in(
  project: String,
  command: String,
  timeout_command: String,
  timeout: Int,
  environment: List(#(String, String)),
) -> Result(#(Int, String), Nil) {
  let arguments = [
    "--kill-after=10",
    int.to_string(timeout),
    "gleam",
    command,
    "--target",
    "erlang",
  ]
  run_command(timeout_command, arguments, in: project, with: environment)
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
  <> case results.shard {
    Whole -> ""
    Part(..) ->
      ",\"shard\":"
      <> json.to_string(json.string(shard_to_string(results.shard)))
  }
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
    use shard <- decode.optional_field("shard", Whole, shard_decoder())
    use rows <- decode.field("mutants", decode.list(row_decoder()))
    decode.success(Results(files:, excluded:, shard:, rows:))
  }
  json.parse(text, decoder) |> result.replace_error(Nil)
}

fn shard_decoder() -> decode.Decoder(Shard) {
  use text <- decode.then(decode.string)
  case parse_shard(text) {
    Ok(shard) -> decode.success(shard)
    Error(Nil) -> decode.failure(Whole, "shard K/N")
  }
}

fn read_results(path: String) -> Result(Results, MutationError) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(FailedToReadFile(path, _)),
  )
  results_from_json(text) |> result.replace_error(NotAResultsFile(path))
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
    |> result.map_error(FailedToWriteFile(directory, _)),
  )
  simplifile.write(path, contents)
  |> result.map_error(FailedToWriteFile(path, _))
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
  percent(detected, of: detected + summary.lived)
}

/// `part` of `whole` to a tenth of a percent, and 100.0% when `whole` is 0.
fn percent(part: Int, of whole: Int) -> String {
  case whole {
    0 -> "100.0%"
    _ -> {
      let tenths = { part * 1000 + whole / 2 } / whole
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
pub fn new_survivors(
  in results: List(Row),
  against baseline: List(Row),
) -> List(Row) {
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
  let new = new_survivors(in: results.rows, against: baseline.rows)
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

/// Whether `results` ran every mutant of every module in `all` that it did not
/// exclude.
pub fn is_full_run(results: Results, all: List(String)) -> Bool {
  results.shard == Whole
  && results.files == select_modules(all:, exclude: results.excluded, files: [])
}

fn merge(paths: List(String)) -> Result(Int, MutationError) {
  use parts <- result.try(list.try_map(paths, read_results))
  use merged <- result.try(
    merge_results(parts) |> result.map_error(CannotMerge),
  )
  use _ <- result.map(write_results(merged))
  io.println(summary_line(merged.rows))
  0
}

/// Why the parts of a sharded run cannot be joined.
pub type MergeError {
  /// No results file was given.
  NoResults
  /// The parts mutated different modules or excluded different ones.
  DifferentRuns
  /// A results file comes from a run without `--shard`.
  NotSharded
  /// A part from 1 to `count` is missing or appears twice, or the parts
  /// disagree on `count`.
  PartsMissingOrRepeated(count: Int)
}

/// Joins the results of every part of one sharded run. The parts must share
/// their modules and exclusions, and each of 1 to N must appear once.
pub fn merge_results(parts: List(Results)) -> Result(Results, MergeError) {
  use first <- result.try(list.first(parts) |> result.replace_error(NoResults))
  use <- bool.guard(
    !list.all(parts, fn(part) {
      part.files == first.files && part.excluded == first.excluded
    }),
    Error(DifferentRuns),
  )
  use shards <- result.try(
    list.try_map(parts, fn(part) {
      case part.shard {
        Part(index:, count:) -> Ok(#(index, count))
        Whole -> Error(NotSharded)
      }
    }),
  )
  use _ <- result.map(covers_every_part(shards))
  Results(
    files: first.files,
    excluded: first.excluded,
    shard: Whole,
    rows: list.flat_map(parts, fn(part) { part.rows }) |> sort_rows,
  )
}

/// Whether `shards` holds each of 1 to N once, all with the same N.
fn covers_every_part(shards: List(#(Int, Int))) -> Result(Nil, MergeError) {
  let count = case shards {
    [#(_, count), ..] -> count
    [] -> 0
  }
  let indices = list.sort(list.map(shards, fn(shard) { shard.0 }), int.compare)
  let expected =
    int.range(from: 1, to: count + 1, with: [], run: fn(acc, index) {
      [index, ..acc]
    })
    |> list.reverse
  case list.all(shards, fn(shard) { shard.1 == count }) && indices == expected {
    True -> Ok(Nil)
    False -> Error(PartsMissingOrRepeated(count:))
  }
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

// Line coverage --------------------------------------------------------------

/// Runs the tests in a fresh `erl` with the modules under `src/` measured by
/// Erlang's `cover`, then writes the counts as LCOV. The line numbers `cover`
/// reports are the lines of the Gleam source. The lines each command in `e2e`
/// reaches are added to those of the tests.
fn coverage(e2e: List(String)) -> Result(Int, MutationError) {
  use erl <- result.try(
    find_executable("erl") |> result.replace_error(ErlMissing),
  )
  let version = case run_command("gleam", ["--version"], in: ".", with: []) {
    Ok(#(0, output)) -> string.trim(output)
    _ -> "nothing"
  }
  use _ <- result.try(check_gleam_version(version))
  use manifest <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(FailedToReadFile("gleam.toml", _)),
  )
  use package <- result.try(
    package_name(manifest) |> result.replace_error(NoPackageName),
  )
  // `gleam run -m metamon/mutation` in a project that depends on metamon
  // compiles only the dependencies, so the project and its tests are built
  // here before `cover` looks for their BEAM files.
  use _ <- result.try(
    case run_inheriting("gleam", ["build", "--target", "erlang"]) {
      Ok(0) -> Ok(Nil)
      _ -> Error(CoverageBuildFailed)
    },
  )
  use sources <- result.try(source_files())
  use tests <- result.try(
    simplifile.get_files("test")
    |> result.map_error(FailedToReadFile("test", _)),
  )
  use packages <- result.try(
    simplifile.read_directory(erlang_build)
    |> result.map_error(FailedToReadFile(erlang_build, _)),
  )
  use _ <- result.try(write_file(counts_path, ""))
  let erlang_modules =
    list.filter(sources, string.ends_with(_, ".erl"))
    |> list.filter_map(test_module)
  let sources = list.filter(sources, string.ends_with(_, ".gleam"))
  let measured = list.map(sources, module_name(_, in: "src/"))
  use contents <- result.try(read_sources(sources))
  // glance is only used to find the lines to skip, so a module it cannot
  // parse is still measured, with none of its lines skipped.
  let skipped =
    dict.to_list(contents)
    |> list.map(fn(entry) {
      #(
        module_name(entry.0, in: "src/"),
        external_lines(entry.1) |> result.unwrap([]),
      )
    })
    |> dict.from_list
  let paths =
    packages
    |> list.sort(string.compare)
    |> list.map(fn(package) { erlang_build <> "/" <> package <> "/ebin" })
  let arguments =
    list.flatten([
      ["-noshell", "-pa", ..paths],
      ["-eval", "metamon_ffi:measure_coverage().", "-extra", counts_path],
      [package, ..measured],
      ["--", ..list.filter_map(tests, test_module)],
    ])
  use status <- result.try(
    run_inheriting(erl, arguments) |> result.replace_error(ErlMissing),
  )
  use status <- result.try(case status {
    0 | 1 -> Ok(status)
    _ -> Error(CoverageFailed(status))
  })
  use counts <- result.try(
    simplifile.read(counts_path)
    |> result.map_error(FailedToReadFile(counts_path, _)),
  )
  use #(e2e_status, e2e_counts) <- result.try(case e2e {
    [] -> Ok(#(0, ""))
    _ -> measure_e2e(e2e, erl:, package:, paths:, measured:, erlang_modules:)
  })
  let #(lcov, summary) = coverage_report(counts <> e2e_counts, skipped)
  use _ <- result.try(write_file(lcov_path, lcov))
  io.println(summary)
  Ok(int.max(status, e2e_status))
}

/// Compiles the package once with its lines counted, runs each command with
/// the escript that runs the program from those modules, and returns 1 when a
/// command fails, 0 otherwise, with the counts of every run of the escript.
fn measure_e2e(
  commands: List(String),
  erl erl: String,
  package package: String,
  paths paths: List(String),
  measured measured: List(String),
  erlang_modules erlang_modules: List(String),
) -> Result(#(Int, String), MutationError) {
  use _ <- result.try(delete_if_present(e2e_path))
  let arguments =
    list.flatten([
      ["-noshell", "-pa", ..paths],
      ["-eval", "metamon_e2e:prepare().", "-extra", e2e_path, package],
      measured,
      ["--", ..erlang_modules],
    ])
  use status <- result.try(
    run_inheriting(erl, arguments) |> result.replace_error(ErlMissing),
  )
  use <- bool.guard(status != 0, Error(E2ePrepareFailed(status)))
  use directory <- result.try(
    simplifile.current_directory()
    |> result.map_error(FailedToReadFile(".", _)),
  )
  let escript = directory <> "/" <> e2e_path <> "/bin/" <> package
  let passed = list.map(commands, run_e2e_command(_, escript))
  let counts_directory = e2e_path <> "/counts"
  use files <- result.try(
    simplifile.get_files(counts_directory)
    |> result.map_error(FailedToReadFile(counts_directory, _)),
  )
  use counts <- result.try(
    list.try_map(files, fn(file) {
      simplifile.read(file) |> result.map_error(FailedToReadFile(file, _))
    }),
  )
  let status = case list.all(passed, fn(ok) { ok }) {
    True -> 0
    False -> 1
  }
  Ok(#(status, string.concat(counts)))
}

/// Runs `command` in `sh` with the escript in `METAMON_COVERAGE_ESCRIPT`, and
/// says so when it fails.
fn run_e2e_command(command: String, escript: String) -> Bool {
  let environment = e2e_variable <> "=" <> escript
  case run_inheriting("env", [environment, "sh", "-c", command]) {
    Ok(0) -> True
    Ok(status) -> {
      io.println_error(
        "the --e2e command exited with "
        <> int.to_string(status)
        <> ": "
        <> command,
      )
      False
    }
    Error(Nil) -> {
      io.println_error("env is not on PATH, so --e2e cannot run: " <> command)
      False
    }
  }
}

/// The value of the `name` line of a `gleam.toml`.
pub fn package_name(manifest: String) -> Result(String, Nil) {
  string.split(manifest, "\n")
  |> list.find_map(fn(line) {
    case string.split_once(string.trim(line), "=") {
      Ok(#(key, value)) ->
        case string.trim(key), string.trim(value) {
          "name", "\"" <> rest -> string.split_once(rest, "\"")
          _, _ -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
  |> result.map(fn(pair) { pair.0 })
}

/// Fails unless `gleam --version` printed 1.19 or later. Older compilers
/// wrote Erlang source, so `cover` reported the lines of that source instead.
pub fn check_gleam_version(version: String) -> Result(Nil, MutationError) {
  let numbers =
    string.replace(version, "gleam ", "")
    |> string.split(".")
    |> list.map(int.parse)
  case numbers {
    [Ok(major), Ok(minor), ..] if major > 1 || major == 1 && minor >= 19 ->
      Ok(Nil)
    _ -> Error(CoverageNeedsNewerGleam(version))
  }
}

/// The Erlang module name of a Gleam file under `root`:
/// `src/a/b.gleam` in `src/` is `a@b`.
fn module_name(path: String, in root: String) -> String {
  path
  |> string.drop_start(string.length(root))
  |> string.drop_end(string.length(".gleam"))
  |> string.replace("/", "@")
}

/// The modules gleeunit runs: every Gleam module under `test/`, and every
/// Erlang module by its file name.
pub fn test_module(path: String) -> Result(String, Nil) {
  case string.ends_with(path, ".gleam"), string.ends_with(path, ".erl") {
    True, _ -> Ok(module_name(path, in: "test/"))
    _, True ->
      string.split(path, "/")
      |> list.last
      |> result.map(string.drop_end(_, string.length(".erl")))
    _, _ -> Error(Nil)
  }
}

/// The lines that declare a function implemented in Erlang. A call to one
/// goes straight to the Erlang function, so `cover` reports its line as never
/// reached.
pub fn external_lines(source: String) -> Result(List(Int), glance.Error) {
  use parsed <- result.map(glance.module(source))
  let bytes = bit_array.from_string(source)
  list.filter_map(parsed.functions, fn(definition) {
    let is_erlang =
      list.any(definition.attributes, fn(attribute) {
        case attribute {
          glance.Attribute(
            name: "external",
            arguments: [glance.Variable(name: "erlang", ..), ..],
          ) -> True
          _ -> False
        }
      })
    use <- bool.guard(!is_erlang, Error(Nil))
    bit_array.slice(bytes, 0, definition.definition.location.start)
    |> result.try(bit_array.to_string)
    |> result.map(fn(before) { list.length(string.split(before, "\n")) })
  })
  |> list.sort(int.compare)
}

/// How many times the tests reached one line of a module.
type Count {
  Count(module: String, line: Int, calls: Int)
}

/// The LCOV file and a summary line for the counts that
/// `metamon_ffi:measure_coverage/0` writes, one `module<TAB>line<TAB>calls`
/// per line. A line that appears more than once, as it does when the tests
/// and an end-to-end suite both reach it, gets the sum of its calls. The
/// lines in `skipped`, by module, are left out.
pub fn coverage_report(
  counts: String,
  skipped: Dict(String, List(Int)),
) -> #(String, String) {
  let by_module =
    string.split(counts, "\n")
    |> list.filter_map(parse_count)
    |> list.filter(fn(count) {
      let lines = dict.get(skipped, count.module) |> result.unwrap([])
      !list.contains(lines, count.line)
    })
    |> list.fold(dict.new(), fn(sums, count) {
      let key = #(count.module, count.line)
      let sum = dict.get(sums, key) |> result.unwrap(0)
      dict.insert(sums, key, sum + count.calls)
    })
    |> dict.to_list
    |> list.map(fn(entry) {
      Count(module: entry.0.0, line: entry.0.1, calls: entry.1)
    })
    |> list.group(fn(count) { count.module })
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(entry) {
      #(entry.0, list.sort(entry.1, fn(a, b) { int.compare(a.line, b.line) }))
    })
  let all = list.flat_map(by_module, fn(entry) { entry.1 })
  let reached = list.count(all, fn(count) { count.calls > 0 })
  #(
    string.concat(
      list.map(by_module, fn(entry) { lcov_record(entry.0, entry.1) }),
    ),
    "line coverage "
      <> percent(reached, of: list.length(all))
      <> ": "
      <> int.to_string(reached)
      <> " of "
      <> int.to_string(list.length(all))
      <> " lines reached",
  )
}

fn parse_count(line: String) -> Result(Count, Nil) {
  case string.split(line, "\t") {
    [module, line, calls] -> {
      use line <- result.try(int.parse(line))
      use calls <- result.map(int.parse(calls))
      Count(module:, line:, calls:)
    }
    _ -> Error(Nil)
  }
}

/// The LCOV record of `module`, whose counts are sorted by line.
fn lcov_record(module: String, counts: List(Count)) -> String {
  let data =
    list.map(counts, fn(count) {
      "DA:"
      <> int.to_string(count.line)
      <> ","
      <> int.to_string(count.calls)
      <> "\n"
    })
  "SF:src/"
  <> string.replace(module, "@", "/")
  <> ".gleam\n"
  <> string.concat(data)
  <> "LF:"
  <> int.to_string(list.length(counts))
  <> "\nLH:"
  <> int.to_string(list.count(counts, fn(count) { count.calls > 0 }))
  <> "\nend_of_record\n"
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

/// The exit status and the combined stdout and stderr of a command run in
/// `directory` with `environment` added to the variables of this process.
/// Only the start and the end of a long output are kept.
@external(erlang, "metamon_ffi", "run_command")
@external(javascript, "../../metamon_ffi.mjs", "run_command")
fn run_command(
  executable: String,
  arguments: List(String),
  in directory: String,
  with environment: List(#(String, String)),
) -> Result(#(Int, String), Nil)

/// The exit status of a command run in the current directory, which writes
/// to the standard output and error of this process.
@external(erlang, "metamon_ffi", "run_inheriting")
@external(javascript, "../../metamon_ffi.mjs", "run_inheriting")
fn run_inheriting(
  executable: String,
  arguments: List(String),
) -> Result(Int, Nil)

@external(erlang, "metamon_ffi", "getenv")
@external(javascript, "../../metamon_ffi.mjs", "getenv")
fn getenv(name: String) -> Result(String, Nil)
