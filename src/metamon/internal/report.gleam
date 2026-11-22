//// Failure-report formatter. Builds the human-readable text that the
//// runner panics with on failure. Kept separate from the runner so
//// the format is easy to test in isolation.

import gleam/dict
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import metamon/internal/coverage
import metamon/internal/diff

/// Identifies the source of a failing input.
pub type InputSource {
  /// The failure happened on the i-th edge value.
  EdgeSource(index: Int)
  /// The failure happened on a randomly generated input.
  RandomSource(seed_value: Int, size: Int, max_size: Int)
}

/// Mode for the metamorphic relation that failed.
pub type MorphMode {
  Plain(transform_name: String)
  Equivariant(input_transform_name: String, output_transform_name: String)
}

/// All the data needed to produce a failure message.
pub type FailureReport {
  FailureReport(
    mr_name: String,
    test_name: String,
    config_seed: Int,
    /// `Some(n)` when the user set `Config.seed` to `Some(n)` and the
    /// runner normalised it into a different canonical state (e.g.
    /// `seed(0)` → `0xDEADBEEF`). The header annotates with
    /// "originally seed(n)" so a user pinning `seed(0)` in source
    /// can map it back to the reported `config seed`. `None` when
    /// the seed was clock-derived (`random_seed`) or already
    /// matched its canonical state.
    config_seed_original: Option(Int),
    runs_done: Int,
    runs_total: Int,
    shrinks_done: Int,
    shrink_capped: Bool,
    morph_mode: Option(MorphMode),
    relation_name: String,
    source_input: String,
    followup_input: String,
    source_output: String,
    followup_output: String,
    input_source: InputSource,
    annotations: List(String),
    footnotes: List(String),
    coverage_snapshot: Option(coverage.Snapshot),
    /// The message of the panic that failed a plain property, from a
    /// last run on the reported input. `None` for metamorphic relations,
    /// and when that last run did not panic.
    panic_message: Option(String),
  )
}

/// Render a source as `edge(i)` or `random(seed=, size=, max_size=)`.
pub fn format_source(source: InputSource) -> String {
  case source {
    EdgeSource(index) -> "edge(" <> int.to_string(index) <> ")"
    RandomSource(seed_value, size, max_size) ->
      "random(seed="
      <> int.to_string(seed_value)
      <> ", size="
      <> int.to_string(size)
      <> ", max_size="
      <> int.to_string(max_size)
      <> ")"
  }
}

/// Render the `config seed:` header value. The canonical state is
/// always shown; when normalisation kicked in (the user passed
/// `seed(n)` whose normalised form differs from `n`), the original
/// integer is appended in parentheses so the user can map the report
/// back to source.
pub fn format_config_seed(state: Int, original: Option(Int)) -> String {
  case original {
    None -> int.to_string(state)
    Some(n) ->
      case n == state {
        True -> int.to_string(state)
        False ->
          int.to_string(state)
          <> " (originally seed("
          <> int.to_string(n)
          <> "))"
      }
  }
}

/// Render a failure report as a single-line JSON object. Stable
/// schema suitable for CI dashboards and LLM-driven analysis. The
/// fields mirror the human-readable layout 1:1 so neither output is
/// the source of truth — the same `FailureReport` produces both.
pub fn render_json(report: FailureReport) -> String {
  let mode = case report.morph_mode {
    None -> json.string("plain")
    Some(Plain(t)) ->
      json.object([
        #("kind", json.string("plain")),
        #("transform", json.string(t)),
      ])
    Some(Equivariant(input_t, output_t)) ->
      json.object([
        #("kind", json.string("equivariant")),
        #("input_transform", json.string(input_t)),
        #("output_transform", json.string(output_t)),
      ])
  }
  let source = case report.input_source {
    EdgeSource(i) ->
      json.object([
        #("kind", json.string("edge")),
        #("index", json.int(i)),
      ])
    RandomSource(seed_value, size, max_size) ->
      json.object([
        #("kind", json.string("random")),
        #("seed", json.int(seed_value)),
        #("size", json.int(size)),
        #("max_size", json.int(max_size)),
      ])
  }
  let coverage_field = case report.coverage_snapshot {
    None -> json.null()
    Some(snap) -> coverage_to_json(snap)
  }
  let config_seed_original_field = case report.config_seed_original {
    None -> json.null()
    Some(n) -> json.int(n)
  }
  json.object([
    #("mr_name", json.string(report.mr_name)),
    #("test_name", json.string(report.test_name)),
    #("config_seed", json.int(report.config_seed)),
    #("config_seed_original", config_seed_original_field),
    #("runs_done", json.int(report.runs_done)),
    #("runs_total", json.int(report.runs_total)),
    #("shrinks_done", json.int(report.shrinks_done)),
    #("shrink_capped", json.bool(report.shrink_capped)),
    #("source", source),
    #("morph_mode", mode),
    #("relation", json.string(report.relation_name)),
    #("source_input", json.string(report.source_input)),
    #("followup_input", json.string(report.followup_input)),
    #("source_output", json.string(report.source_output)),
    #("followup_output", json.string(report.followup_output)),
    #("annotations", json.array(report.annotations, json.string)),
    #("footnotes", json.array(report.footnotes, json.string)),
    #("coverage", coverage_field),
    #("panic_message", json.nullable(report.panic_message, json.string)),
  ])
  |> json.to_string
}

fn coverage_to_json(snap: coverage.Snapshot) -> json.Json {
  json.object([
    #("total", json.int(snap.total)),
    #(
      "requirements",
      json.array(snap.requirements, fn(req: coverage.Requirement) {
        json.object([
          #("label", json.string(req.label)),
          #("target_pct", json.float(req.target_pct)),
          #("hits", json.int(req.hits)),
          #("actual_pct", json.float(coverage.actual_pct(req.hits, snap.total))),
        ])
      }),
    ),
    #(
      "collected",
      json.array(classified(snap), fn(pair) {
        json.object([
          #("label", json.string(pair.0)),
          #("count", json.int(pair.1)),
        ])
      }),
    ),
  ])
}

/// Render a failure report. The output is multi-line and ends with a
/// "reproduce" stanza users can paste into a Gleam test.
pub fn render(report: FailureReport) -> String {
  let header_block = header_lines(report) |> string.join("\n")
  let body_block = body_lines(report) |> string.join("\n\n")
  let extras_block = extras_lines(report) |> string.join("\n\n")
  let reproduce_block = reproduce_lines(report) |> string.join("\n")
  let blocks =
    [header_block, body_block, extras_block, reproduce_block]
    |> list.filter(fn(b) { b != "" })
  string.join(blocks, "\n\n")
}

fn header_lines(report: FailureReport) -> List(String) {
  let title = case report.morph_mode {
    None -> "× property failed"
    Some(_) -> "× metamorphic relation `" <> report.mr_name <> "` failed"
  }
  let source = format_source(report.input_source)
  let shrinks_label = case report.shrink_capped {
    True -> int.to_string(report.shrinks_done) <> "+ (limit reached)"
    False -> int.to_string(report.shrinks_done)
  }
  [
    title,
    "  test:        " <> report.test_name,
    "  source:      " <> source,
    "  config seed: "
      <> format_config_seed(report.config_seed, report.config_seed_original),
    "  runs:        "
      <> int.to_string(report.runs_done)
      <> " / "
      <> int.to_string(report.runs_total),
    "  shrinks:     " <> shrinks_label,
  ]
}

fn body_lines(report: FailureReport) -> List(String) {
  let transform_block = case report.morph_mode {
    None -> []
    Some(Plain(t)) -> ["  transform:   `" <> t <> "`"]
    Some(Equivariant(input_t, output_t)) -> [
      "  input:       `" <> input_t <> "`",
      "  output:      `" <> output_t <> "`",
    ]
  }
  let relation_block = case report.morph_mode {
    None -> []
    Some(_) -> ["  relation:    `" <> report.relation_name <> "`"]
  }
  let inputs = case report.morph_mode {
    None -> [
      "  source input  (shrunk):\n    " <> report.source_input,
      ..panic_lines(report.panic_message)
    ]
    Some(_) -> [
      "  source input  (shrunk):\n    " <> report.source_input,
      "  follow-up input  (= transform(source)):\n    " <> report.followup_input,
      "  source output:\n    " <> report.source_output,
      "  follow-up output:\n    " <> report.followup_output,
    ]
  }
  let diff_block = case report.morph_mode {
    Some(_) -> [
      "  diff (source_output vs follow-up_output):\n"
      <> indent(
        diff.render(diff.diff_inspected(
          report.source_output,
          report.followup_output,
        )),
        "    ",
      ),
    ]
    None -> []
  }
  list.flatten([
    list_join_block(list.append(transform_block, relation_block)),
    inputs,
    diff_block,
  ])
}

fn panic_lines(message: Option(String)) -> List(String) {
  case message {
    None -> []
    Some(text) -> ["  panic message:\n" <> indent(text, "    ")]
  }
}

fn list_join_block(lines: List(String)) -> List(String) {
  case lines {
    [] -> []
    items -> [string.join(items, "\n")]
  }
}

fn extras_lines(report: FailureReport) -> List(String) {
  let annotations_block = case report.annotations {
    [] -> []
    items -> [
      "  annotations:\n"
      <> string.join(list.map(items, fn(a) { "    - " <> a }), "\n"),
    ]
  }
  let footnotes_block = case report.footnotes {
    [] -> []
    items -> [
      "  footnotes:\n"
      <> string.join(list.map(items, fn(f) { "    - " <> f }), "\n"),
    ]
  }
  let coverage_block = case report.coverage_snapshot {
    None -> []
    Some(snap) ->
      case coverage_lines(snap) {
        [] -> []
        lines -> ["  coverage:\n" <> string.join(lines, "\n")]
      }
  }
  list.flatten([annotations_block, footnotes_block, coverage_block])
}

fn coverage_lines(snap: coverage.Snapshot) -> List(String) {
  let total = snap.total
  let req_lines =
    list.map(snap.requirements, fn(req: coverage.Requirement) {
      let pct = coverage.actual_pct(req.hits, total)
      "    "
      <> req.label
      <> ": "
      <> int.to_string(req.hits)
      <> "/"
      <> int.to_string(total)
      <> " ("
      <> float.to_string(pct)
      <> "%) target≥"
      <> float.to_string(req.target_pct)
      <> "%"
    })
  let classified_lines =
    classified(snap)
    |> list.map(fn(pair) { "    " <> pair.0 <> ": " <> int.to_string(pair.1) })
  list.append(req_lines, classified_lines)
}

/// The hits of every label that has no `cover` requirement, by label.
fn classified(snap: coverage.Snapshot) -> List(#(String, Int)) {
  let required = list.map(snap.requirements, fn(req) { req.label })
  dict.to_list(snap.counts)
  |> list.filter(fn(pair) { !list.contains(required, pair.0) })
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
}

fn reproduce_lines(report: FailureReport) -> List(String) {
  // The shrunk input is already shown in `source input (shrunk)`
  // earlier in the report. The reproduce block re-states the input
  // alongside an `assert_morph` (or a direct call) call site so users
  // can paste it into a regression test verbatim.
  case report.morph_mode {
    None -> [
      "  reproduce (paste into a test):",
      "    // The property failed for this input. To pin it as a",
      "    // regression, store it explicitly and call the property.",
      "    let input = " <> report.source_input,
      "    property(input)",
    ]
    Some(_) -> [
      "  reproduce (paste into a test):",
      "    // The MR failed for this input. To pin it as a regression,",
      "    // call assert_morph with the shrunk input and the same MR.",
      "    let input = " <> report.source_input,
      "    metamon.assert_morph(input, mr, f)",
    ]
  }
}

fn indent(block: String, prefix: String) -> String {
  string.split(block, "\n")
  |> list.map(fn(line) { prefix <> line })
  |> string.join("\n")
}
