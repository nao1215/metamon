//// Tests for `metamon/mutation`: finding and applying mutants, the command
//// line, the results file, the gate and the table in doc/testing.md.

import glance
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/generator
import metamon/internal/mutant
import metamon/internal/mutation.{
  CompileError, Killed, Lived, Results, Row, Summary, TimedOut,
}
import simplifile

fn mutators(source: String) -> List(String) {
  let assert Ok(found) = mutant.find(file: "src/m.gleam", source:)
  list.map(found, fn(found) { found.mutator })
}

fn applied(source: String) -> List(String) {
  let assert Ok(found) = mutant.find(file: "src/m.gleam", source:)
  list.map(found, fn(found) {
    let assert Ok(text) = mutant.apply(source:, mutant: found)
    text
  })
}

// Finding mutants -----------------------------------------------------------

pub fn every_operator_has_its_replacement_test() {
  let cases = [
    #("a && b", "&& -> ||"),
    #("a || b", "|| -> &&"),
    #("a == b", "== -> !="),
    #("a != b", "!= -> =="),
    #("a < b", "< -> <="),
    #("a <= b", "<= -> <"),
    #("a > b", "> -> >="),
    #("a >= b", ">= -> >"),
    #("a <. b", "<. -> <=."),
    #("a <=. b", "<=. -> <."),
    #("a >. b", ">. -> >=."),
    #("a >=. b", ">=. -> >."),
    #("a + b", "+ -> -"),
    #("a - b", "- -> +"),
    #("a * b", "* -> /"),
    #("a / b", "/ -> *"),
    #("a % b", "% -> *"),
    #("a +. b", "+. -> -."),
    #("a -. b", "-. -> +."),
    #("a *. b", "*. -> /."),
    #("a /. b", "/. -> *."),
  ]
  list.each(cases, fn(pair) {
    let source = "pub fn f(a, b) { " <> pair.0 <> " }\n"
    assert mutators(source) == [pair.1]
  })
}

pub fn booleans_and_negation_are_mutated_test() {
  assert mutators("fn f(a) { #(True, False, !a) }")
    == ["True -> False", "False -> True", "drop !"]
  assert applied("fn f(a) { !a }") == ["fn f(a) { a }"]
}

pub fn pipes_concatenation_and_literals_are_left_alone_test() {
  assert mutators(
      "fn f(a) { a |> g <> \"a + b == c\" <> <<1:size(8)>> |> h(1 - 2) }",
    )
    == ["- -> +"]
}

pub fn patterns_and_guards_are_handled_test() {
  let source =
    "fn f(a) {
  case a {
    [x, ..] if x > 0 -> True
    _ -> a == []
  }
}"
  assert mutators(source) == ["> -> >=", "True -> False", "== -> !="]
}

pub fn an_operator_in_a_comment_between_operands_is_skipped_test() {
  let source =
    "fn f(a, b) {
  a
  // a + b
  + b
}"
  assert applied(source)
    == [
      "fn f(a, b) {
  a
  // a + b
  - b
}",
    ]
}

pub fn nested_expressions_are_all_found_test() {
  let source =
    "fn f(a, b) {
  let g = fn(x) { x * 2 }
  use y <- list.map({ [a + 1, ..b] })
  #(g(y - 1), Rec(..r, n: y / 2), a.0 % 3)
}"
  assert mutators(source) == ["* -> /", "+ -> -", "- -> +", "/ -> *", "% -> *"]
}

pub fn line_text_and_column_identify_the_change_test() {
  let assert Ok([first, second]) =
    mutant.find(file: "src/m.gleam", source: "fn f(a) {\n    a + a + a\n}\n")
  assert first.line == 2
  assert first.text == "a + a + a"
  assert #(first.column, second.column) == #(2, 6)
  assert first.function == "f"
}

pub fn a_module_glance_cannot_parse_is_an_error_test() {
  let assert Error(_) = mutant.find(file: "src/m.gleam", source: "fn f( {")
}

/// Every mutant of every module in this repository applies, changes only the
/// text it names, and leaves a module glance can still parse. Erlang only:
/// the tool runs there, and on JavaScript glance reports positions after a
/// non-ASCII character that are not byte offsets.
pub fn mutants_of_real_modules_apply_and_parse_test() {
  use <- on_erlang
  let assert Ok(files) = simplifile.get_files("src")
  files
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.each(fn(file) {
    let assert Ok(source) = simplifile.read(file)
    let assert Ok(found) = mutant.find(file:, source:)
    list.each(found, fn(found) {
      let assert Ok(mutated) = mutant.apply(source:, mutant: found)
      assert string.byte_size(mutated)
        == string.byte_size(source)
        - found.length
        + string.byte_size(found.replacement)
      let original = case string.split_once(found.mutator, " -> ") {
        Ok(#(original, _)) -> original
        Error(Nil) -> string.drop_start(found.mutator, 5)
      }
      let assert Ok(changed) =
        bit_array.slice(
          bit_array.from_string(source),
          found.offset,
          found.length,
        )
      assert bit_array.to_string(changed) == Ok(original)
      assert string.starts_with(
        string.drop_start(found.text, found.column),
        original,
      )
      let assert Ok(_) = glance.module(mutated)
    })
  })
}

/// Lines added above a function move its mutants down but keep the text,
/// column, mutator and function, which is what the gate matches on.
pub fn moving_code_keeps_the_match_key_test() {
  let source =
    "pub fn f(a, b) {\n  case a > b && !b {\n    True -> a - b\n    False -> a * 2\n  }\n}\n"
  let assert Ok(before) = mutant.find(file: "src/m.gleam", source:)
  metamon.forall(generator.int(generator.range(0, 30)), fn(lines) {
    let moved = string.repeat("// moved\n", lines) <> source
    let assert Ok(after) = mutant.find(file: "src/m.gleam", source: moved)
    assert list.map(after, fn(found) {
        #(found.line - lines, found.text, found.column, found.mutator)
      })
      == list.map(before, fn(found) {
        #(found.line, found.text, found.column, found.mutator)
      })
  })
}

// Command line --------------------------------------------------------------

pub fn arguments_are_parsed_test() {
  assert mutation.parse_arguments(["run"])
    == Ok(mutation.Run(workers: 4, exclude: [], files: []))
  assert mutation.parse_arguments([
      "run", "--workers", "2", "--exclude", "src/a.gleam", "src/b.gleam",
      "--exclude", "src/c.gleam",
    ])
    == Ok(
      mutation.Run(workers: 2, exclude: ["src/a.gleam", "src/c.gleam"], files: [
        "src/b.gleam",
      ]),
    )
  assert mutation.parse_arguments(["list", "src/a.gleam"])
    == Ok(mutation.ListMutants(exclude: [], files: ["src/a.gleam"]))
  assert mutation.parse_arguments(["gate"]) == Ok(mutation.Gate)
  assert mutation.parse_arguments(["baseline"]) == Ok(mutation.Baseline)
  assert mutation.parse_arguments(["doc-check"]) == Ok(mutation.DocCheck)
}

pub fn bad_arguments_print_the_usage_test() {
  list.each(
    [
      [],
      ["walk"],
      ["gate", "extra"],
      ["run", "--workers"],
      ["run", "--workers", "0"],
      ["run", "--workers", "x"],
      ["run", "--exclude"],
      ["run", "--verbose"],
    ],
    fn(arguments) {
      assert mutation.parse_arguments(arguments) == Error(Nil)
    },
  )
}

pub fn a_failure_without_passed_tests_did_not_compile_test() {
  assert mutation.classify_failure("error: Unknown variable\n") == CompileError
  assert mutation.classify_failure("1 passed, 1 failures\nerror: boom")
    == Killed
  assert mutation.classify_failure("panic: assertion failed") == Killed
}

// Results -------------------------------------------------------------------

fn row_generator() -> generator.Generator(mutation.Row) {
  let text =
    generator.string(
      of: generator.Unicode,
      length: generator.range(from: 0, to: 12),
    )
  generator.map6(
    generator.element_of(["src/a.gleam", "src/b/c.gleam"]),
    generator.int(generator.range(1, 500)),
    generator.int(generator.range(0, 80)),
    text,
    generator.element_of(["+ -> -", "drop !", "True -> False"]),
    generator.tuple2(
      generator.one_of([text, generator.return("},{\"a\":\"\\n\"}")]),
      generator.element_of([Killed, Lived, TimedOut, CompileError]),
    ),
    fn(file, line, column, function, mutator, rest) {
      Row(
        file:,
        line:,
        column:,
        function:,
        mutator:,
        text: rest.0,
        status: rest.1,
      )
    },
  )
}

pub fn results_survive_a_round_trip_through_json_test() {
  let results =
    generator.map2(
      generator.list_of(row_generator(), length: generator.range(0, 8)),
      generator.list_of(
        generator.element_of(["src/x.gleam", "src/y.gleam"]),
        length: generator.range(0, 2),
      ),
      fn(rows, excluded) {
        Results(files: ["src/a.gleam", "src/b/c.gleam"], excluded:, rows:)
      },
    )
  metamon.forall_round_trip(
    generator: results,
    name: "mutation results JSON",
    encode: mutation.results_to_json,
    decode: mutation.results_from_json,
  )
}

pub fn results_without_excluded_files_still_load_test() {
  let assert Ok(results) =
    mutation.results_from_json("{\"files\":[\"src/a.gleam\"],\"mutants\":[]}")
  assert results == Results(files: ["src/a.gleam"], excluded: [], rows: [])
  assert mutation.results_from_json("{\"files\":[]}") == Error(Nil)
  assert mutation.results_from_json(
      "{\"files\":[],\"mutants\":[{\"file\":\"a\",\"line\":1,\"column\":0,\"function\":\"f\",\"mutator\":\"m\",\"text\":\"t\",\"status\":\"ALIVE\"}]}",
    )
    == Error(Nil)
}

pub fn the_score_counts_timeouts_as_killed_test() {
  assert mutation.score(Summary(
      killed: 0,
      lived: 0,
      timed_out: 0,
      compile_error: 3,
    ))
    == "100.0%"
  assert mutation.score(Summary(
      killed: 2,
      lived: 1,
      timed_out: 0,
      compile_error: 9,
    ))
    == "66.7%"
  assert mutation.score(Summary(
      killed: 1,
      lived: 1,
      timed_out: 1,
      compile_error: 0,
    ))
    == "66.7%"
  assert mutation.score(Summary(
      killed: 0,
      lived: 7,
      timed_out: 0,
      compile_error: 0,
    ))
    == "0.0%"
  assert mutation.score(Summary(
      killed: 807,
      lived: 125,
      timed_out: 3,
      compile_error: 0,
    ))
    == "86.6%"
}

pub fn summarise_counts_every_status_test() {
  metamon.forall(
    generator.list_of(row_generator(), length: generator.range(0, 20)),
    fn(rows) {
      let summary = mutation.summarise(rows)
      assert summary.killed
        + summary.lived
        + summary.timed_out
        + summary.compile_error
        == list.length(rows)
      assert summary.lived == list.count(rows, fn(row) { row.status == Lived })
    },
  )
}

// Gate and baseline ---------------------------------------------------------

fn row(line: Int, column: Int, status: mutation.Status) -> mutation.Row {
  Row(
    file: "src/a.gleam",
    line:,
    column:,
    function: "f",
    mutator: "+ -> -",
    text: "a + b",
    status:,
  )
}

pub fn a_known_survivor_on_another_line_is_not_new_test() {
  assert mutation.new_survivors([row(10, 2, Lived)], [row(42, 2, Lived)]) == []
}

pub fn a_survivor_the_baseline_does_not_list_is_new_test() {
  assert mutation.new_survivors([row(10, 2, Lived)], [row(10, 6, Lived)])
    == [row(10, 6, Lived)]
  assert mutation.new_survivors([row(10, 2, Killed)], [row(10, 2, Lived)])
    == [row(10, 2, Lived)]
  assert mutation.new_survivors([row(10, 2, Lived)], [row(10, 2, Killed)]) == []
}

/// The baseline never reports itself.
pub fn a_run_matching_the_baseline_passes_the_gate_test() {
  metamon.forall(
    generator.list_of(row_generator(), length: generator.range(0, 20)),
    fn(rows) {
      assert mutation.new_survivors(rows, rows) == []
    },
  )
}

pub fn rows_sort_by_file_line_column_and_mutator_test() {
  let rows = [row(3, 1, Lived), row(1, 5, Lived), row(1, 2, Killed)]
  assert mutation.sort_rows(rows)
    == [row(1, 2, Killed), row(1, 5, Lived), row(3, 1, Lived)]
}

pub fn the_table_lists_each_module_and_the_total_test() {
  let rows = [
    row(1, 0, Killed),
    row(2, 0, Lived),
    Row(..row(1, 0, TimedOut), file: "src/b/c.gleam"),
  ]
  assert mutation.table(rows)
    == "| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `a` | 1 | 1 | 0 | 50.0% |
| `b/c` | 0 | 0 | 1 | 100.0% |
| all | 1 | 1 | 1 | 66.7% |"
}

pub fn the_document_changes_only_between_the_markers_test() {
  let text =
    "# Testing\n\nBefore.\n<!-- mutation:start -->\nold table\n<!-- mutation:end -->\nAfter.\n"
  let rows = [row(1, 0, Killed)]
  let assert Ok(rendered) = mutation.render_document(text, rows)
  assert rendered
    == "# Testing\n\nBefore.\n<!-- mutation:start -->\n"
    <> mutation.table(rows)
    <> "\n<!-- mutation:end -->\nAfter.\n"
  assert mutation.render_document(rendered, rows) == Ok(rendered)
  assert mutation.render_document("# Testing\n", rows) == Error(Nil)
  assert mutation.render_document("<!-- mutation:start -->\n", rows)
    == Error(Nil)
}

@external(erlang, "mutation_test_ffi", "on_erlang")
fn on_erlang(run: fn() -> Nil) -> Nil {
  let _ = run
  Nil
}

// Choosing and running ------------------------------------------------------

pub fn every_module_is_chosen_unless_excluded_test() {
  let all = ["src/b.gleam", "src/a.gleam", "src/a_ffi.erl", "src/c.gleam"]
  assert mutation.select_modules(all:, exclude: [], files: [])
    == ["src/a.gleam", "src/b.gleam", "src/c.gleam"]
  assert mutation.select_modules(all:, exclude: ["src/b.gleam"], files: [])
    == ["src/a.gleam", "src/c.gleam"]
  assert mutation.select_modules(all:, exclude: ["src/b.gleam"], files: [
      "src/c.gleam",
      "src/b.gleam",
      "src/c.gleam",
    ])
    == ["src/c.gleam"]
}

/// The workers share the mutants: each one runs once, in order.
pub fn the_workers_share_every_mutant_once_test() {
  let items =
    generator.list_of(
      generator.int(generator.range(0, 99)),
      length: generator.range(0, 30),
    )
  metamon.forall(
    generator.tuple2(items, generator.int(generator.range(1, 6))),
    fn(pair) {
      let #(items, workers) = pair
      let shares =
        workers_up_to(workers)
        |> list.map(fn(worker) {
          mutation.share(items, of: workers, for: worker)
        })
      assert list.flatten(shares) |> list.length == list.length(items)
      assert list.map(shares, list.length)
        == workers_up_to(workers)
        |> list.map(fn(worker) {
          { list.length(items) - worker + workers - 1 } / workers
        })
    },
  )
  assert mutation.share([0, 1, 2, 3, 4, 5, 6], of: 3, for: 1) == [1, 4]
}

pub fn a_mutant_gets_four_times_the_clean_run_test() {
  assert mutation.mutant_timeout(0) == 60
  assert mutation.mutant_timeout(15_000) == 60
  assert mutation.mutant_timeout(16_000) == 64
  assert mutation.mutant_timeout(100_500) == 402
}

pub fn the_copy_leaves_out_build_output_and_git_test() {
  assert mutation.copied_entries([
      "gleam.toml", "build", "src", ".git", "test", "node_modules", "README.md",
    ])
    == ["gleam.toml", "src", "test", "README.md"]
}

pub fn a_survivor_is_retried_test() {
  let killed_on = fn(attempt) {
    fn(number) {
      case number == attempt {
        True -> Killed
        False -> Lived
      }
    }
  }
  assert mutation.retry_while_lived(2, killed_on(2)) == Killed
  assert mutation.retry_while_lived(1, killed_on(2)) == Lived
  assert mutation.retry_while_lived(0, killed_on(0)) == Killed
  assert mutation.retry_while_lived(2, fn(_) { TimedOut }) == TimedOut
}

pub fn a_baseline_needs_every_module_that_is_not_excluded_test() {
  let all = ["src/a.gleam", "src/b.gleam", "src/gen.gleam"]
  let results = fn(files, excluded) { Results(files:, excluded:, rows: []) }
  assert mutation.is_full_run(
    results(["src/a.gleam", "src/b.gleam"], ["src/gen.gleam"]),
    all,
  )
  assert !mutation.is_full_run(results(["src/a.gleam"], ["src/gen.gleam"]), all)
  assert !mutation.is_full_run(results(["src/a.gleam", "src/b.gleam"], []), all)
}

pub fn the_document_check_compares_the_table_test() {
  let rows = [row(1, 0, Killed)]
  let assert Ok(current) =
    mutation.render_document(
      "<!-- mutation:start -->\n<!-- mutation:end -->\n",
      rows,
    )
  assert mutation.document_matches(current, rows)
  assert !mutation.document_matches(current, [row(1, 0, Lived)])
  assert mutation.document_matches("# Testing\n", rows)
}

fn workers_up_to(count: Int) -> List(Int) {
  int.range(from: 0, to: count, with: [], run: fn(acc, index) { [index, ..acc] })
  |> list.reverse
}
