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
import metamon/coverage
import metamon/diff

/// Identifies the source of a failing input.
pub type InputSource {
  /// The failure happened on the i-th edge value.
  EdgeSource(index: Int)
  /// The failure happened on a randomly generated input.
  RandomSource(seed_value: Int, size: Int)
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
    diff_enabled: Bool,
    annotations: List(String),
    footnotes: List(String),
    coverage_snapshot: Option(coverage.Snapshot),
  )
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
    RandomSource(seed_value, size) ->
      json.object([
        #("kind", json.string("random")),
        #("seed", json.int(seed_value)),
        #("size", json.int(size)),
      ])
  }
  let coverage_field = case report.coverage_snapshot {
    None -> json.null()
    Some(snap) -> coverage_to_json(snap)
  }
  json.object([
    #("mr_name", json.string(report.mr_name)),
    #("test_name", json.string(report.test_name)),
    #("config_seed", json.int(report.config_seed)),
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
  ])
  |> json.to_string
}

fn coverage_to_json(snap: coverage.Snapshot) -> json.Json {
  json.object([
    #("total", json.int(snap.total)),
    #(
      "requirements",
      json.array(coverage.requirements_of(snap), fn(req: coverage.Requirement) {
        json.object([
          #("label", json.string(req.label)),
          #("target_pct", json.float(coverage.target_pct_of(req, snap.total))),
          #("hits", json.int(req.hits)),
          #("actual_pct", json.float(coverage.actual_pct(req.hits, snap.total))),
        ])
      }),
    ),
    #(
      "collected",
      json.array(dict.to_list(coverage.collected_of(snap)), fn(pair) {
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
  let source = case report.input_source {
    EdgeSource(idx) -> "edge(" <> int.to_string(idx) <> ")"
    RandomSource(seed_value, size) ->
      "random(seed="
      <> int.to_string(seed_value)
      <> ", size="
      <> int.to_string(size)
      <> ")"
  }
  let shrinks_label = case report.shrink_capped {
    True -> int.to_string(report.shrinks_done) <> "+ (limit reached)"
    False -> int.to_string(report.shrinks_done)
  }
  [
    title,
    "  test:        " <> report.test_name,
    "  source:      " <> source,
    "  config seed: " <> int.to_string(report.config_seed),
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
  let inputs = [
    "  source input  (shrunk):\n    " <> report.source_input,
    "  follow-up input  (= transform(source)):\n    " <> report.followup_input,
    "  source output:\n    " <> report.source_output,
    "  follow-up output:\n    " <> report.followup_output,
  ]
  let diff_block = case report.diff_enabled, report.morph_mode {
    True, Some(_) -> [
      "  diff (source_output vs follow-up_output):\n"
      <> indent(
        diff.render(diff.diff(report.source_output, report.followup_output)),
        "    ",
      ),
    ]
    _, _ -> []
  }
  list.flatten([
    list_join_block(list.append(transform_block, relation_block)),
    inputs,
    diff_block,
  ])
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
    list.map(coverage.requirements_of(snap), fn(req: coverage.Requirement) {
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
      <> float.to_string(coverage.target_pct_of(req, total))
      <> "%"
    })
  let collected = coverage.collected_of(snap)
  let collected_lines =
    dict.to_list(collected)
    |> list.map(fn(pair) { "    " <> pair.0 <> ": " <> int.to_string(pair.1) })
  list.append(req_lines, collected_lines)
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
      "    // regression, store it explicitly and assert directly.",
      "    let input = " <> report.source_input,
      "    should.be_true(property(input))",
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
