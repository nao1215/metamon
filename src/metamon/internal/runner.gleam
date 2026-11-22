//// The actual property / metamorphic test loop. Public users should
//// not import this module directly — the entry points are exposed as
//// `metamon.forall`, `metamon.forall_morph`, and friends.
////
//// Responsibilities:
////   * Drain the generator's `edges` first, then fall back to random
////     generation for the remaining runs.
////   * On failure, walk the rose tree to shrink the source input
////     (subject to the configured shrink limit).
////   * Reset and read the per-process annotate/coverage state.
////   * Build a `FailureReport` and panic with its rendered form.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import metamon/annotate
import metamon/coverage
import metamon/generator.{type Generator}
import metamon/internal/regression
import metamon/internal/report.{
  type FailureReport, type InputSource, type MorphMode, EdgeSource, Equivariant,
  FailureReport, Plain, RandomSource,
} as report_module
import metamon/internal/seed.{type Seed} as seed_module
import metamon/internal/tree.{type Tree}
import metamon/relation.{type Relation}
import metamon/transform.{type Transform}
import simplifile

/// Internal description of a metamorphic relation. Built from
/// `metamon.mr` and `metamon.mr_equivariant`. Opaque so the variant
/// shape can change without breaking downstream test files.
pub opaque type MorphSpec(a, b) {
  PlainSpec(name: String, transform: Transform(a), relation: Relation(b))
  EquivariantSpec(
    name: String,
    input_transform: Transform(a),
    output_transform: Transform(b),
    relation: Relation(b),
  )
}

/// Smart constructor for the Plain MR shape (`f(T(x))` and `f(x)`
/// are related by `R`).
pub fn plain(
  name: String,
  transform: Transform(a),
  relation: Relation(b),
) -> MorphSpec(a, b) {
  PlainSpec(name: name, transform: transform, relation: relation)
}

/// Smart constructor for the Equivariant MR shape (`f(T(x))` and
/// `U(f(x))` are related by `R`).
pub fn equivariant(
  name: String,
  input_transform: Transform(a),
  output_transform: Transform(b),
  relation: Relation(b),
) -> MorphSpec(a, b) {
  EquivariantSpec(
    name: name,
    input_transform: input_transform,
    output_transform: output_transform,
    relation: relation,
  )
}

/// Public accessor for the MR's user-visible name.
pub fn morph_name(spec: MorphSpec(a, b)) -> String {
  spec_name(spec)
}

/// The configuration of one run, built and checked by `settings`.
pub type Settings {
  Settings(
    runs: Int,
    seed: Seed,
    max_size: Int,
    shrink_limit: Int,
    max_edges: Int,
    regression_file: Option(String),
    json: Bool,
  )
}

/// Check the configuration fields and build the settings of one run.
/// `seed` is `None` for a seed drawn from the clock.
///
/// Panics with a message naming the field when `runs`, `max_size`,
/// `shrink_limit` or `max_edges` is not positive, or `regression_file`
/// is `Some("")`.
pub fn settings(
  runs runs: Int,
  seed seed: Option(Int),
  max_size max_size: Int,
  shrink_limit shrink_limit: Int,
  max_edges max_edges: Int,
  regression_file regression_file: Option(String),
  json json: Bool,
) -> Settings {
  require_positive("runs", runs)
  require_positive("max_size", max_size)
  require_positive("shrink_limit", shrink_limit)
  require_positive("max_edges", max_edges)
  case regression_file {
    Some("") ->
      panic as "metamon: Config.regression_file must not be Some(\"\") (use None to turn the regression file off)"
    _ -> Nil
  }
  let seed = case seed {
    Some(value) -> seed_module.seed(value)
    None -> seed_module.random_seed()
  }
  Settings(
    runs: runs,
    seed: seed,
    max_size: max_size,
    shrink_limit: shrink_limit,
    max_edges: max_edges,
    regression_file: regression_file,
    json: json,
  )
}

fn require_positive(field: String, value: Int) -> Nil {
  case value > 0 {
    True -> Nil
    False ->
      panic as {
        "metamon: Config."
        <> field
        <> " must be > 0 (got "
        <> int.to_string(value)
        <> ")"
      }
  }
}

/// Run a property test (no metamorphic transform). `regression_key`
/// names the property's entries in the regression file.
pub fn run_forall(
  cfg: Settings,
  test_name: String,
  regression_key: String,
  gen: Generator(a),
  property: fn(a) -> Bool,
) -> Nil {
  let check =
    Check(
      regression_key: regression_key,
      coverage_name: None,
      holds: property,
      report: fn(failure) { forall_failure(cfg, test_name, property, failure) },
    )
  run_check(cfg, test_name, gen, check) |> finish
}

/// Run a metamorphic relation against `f` for many inputs.
pub fn run_forall_morph(
  cfg: Settings,
  test_name: String,
  gen: Generator(a),
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
) -> Nil {
  run_check(cfg, test_name, gen, morph_check(cfg, test_name, spec, f))
  |> finish
}

fn morph_check(
  cfg: Settings,
  test_name: String,
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
) -> Check(a) {
  Check(
    regression_key: spec_name(spec),
    coverage_name: Some(spec_name(spec)),
    holds: fn(input) { evaluate_spec(spec, f, input).holds },
    report: fn(failure) { morph_failure(cfg, test_name, spec, f, failure) },
  )
}

/// Run a metamorphic relation against a single input. No generator.
pub fn run_assert_morph(
  test_name: String,
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  input: a,
) -> Nil {
  reset_state()
  let evaluation = evaluate_spec(spec, f, input)
  case evaluation.holds {
    True -> Nil
    False -> {
      let report = morph_failure_static(test_name, spec, input, evaluation)
      panic_with(report_module.render(report))
    }
  }
}

fn render_for(cfg: Settings, report: FailureReport) -> String {
  case cfg.json {
    False -> report_module.render(report)
    True -> report_module.render_json(report)
  }
}

/// Run multiple metamorphic specs against the same generator + `f`.
/// Each spec is run independently; failures are collected and the
/// runner panics at the end if any spec failed.
pub fn run_forall_morphs(
  cfg: Settings,
  test_name: String,
  gen: Generator(a),
  specs: List(MorphSpec(a, b)),
  f: fn(a) -> b,
) -> Nil {
  case specs {
    [] ->
      panic_with(
        "metamon.forall_morphs: empty MR list (vacuous test). Pass at least one MR or use forall(...) for a single-input property.",
      )
    _ -> Nil
  }
  let collected =
    list.fold(specs, [], fn(reports, spec) {
      case
        run_check(cfg, test_name, gen, morph_check(cfg, test_name, spec, f))
      {
        Done -> reports
        Halted(text) -> [text, ..reports]
      }
    })
  case collected {
    [] -> Nil
    failures ->
      panic_with(
        "× one or more metamorphic relations failed\n\n"
        <> string.join(list.reverse(failures), "\n\n---\n\n"),
      )
  }
}

// ---------- iteration ----------

type Step {
  Continue
  Stop(report_text: String)
}

type Outcome {
  Done
  Halted(report_text: String)
}

fn iterate_inputs(
  cfg: Settings,
  gen: Generator(a),
  body: fn(a, InputSource, Int) -> Step,
) -> Outcome {
  let edges = generator.edges_of(gen) |> list.take(cfg.max_edges)
  let edge_count = list.length(edges)
  let run_total = total_runs(cfg)
  case run_edges(edges, 0, body) {
    Halted(text) -> Halted(text)
    Done -> {
      let remaining = run_total - edge_count
      case remaining <= 0 {
        True -> Done
        False -> {
          let sizes = Sizes(total: run_total, max: cfg.max_size)
          run_random(gen, sizes, edge_count, remaining, cfg.seed, body)
        }
      }
    }
  }
}

fn run_edges(
  edges: List(a),
  index: Int,
  body: fn(a, InputSource, Int) -> Step,
) -> Outcome {
  case edges {
    [] -> Done
    [first, ..rest] ->
      case body(first, EdgeSource(index), index) {
        Continue -> run_edges(rest, index + 1, body)
        Stop(text) -> Halted(text)
      }
  }
}

/// The run count and `max_size`, read once per property: the run count
/// reads `METAMON_RUNS_MULTIPLIER` from the environment.
type Sizes {
  Sizes(total: Int, max: Int)
}

fn run_random(
  gen: Generator(a),
  sizes: Sizes,
  start_index: Int,
  remaining: Int,
  s: Seed,
  body: fn(a, InputSource, Int) -> Step,
) -> Outcome {
  case remaining <= 0 {
    True -> Done
    False -> {
      let #(here, rest_seed) = seed_module.split(s)
      let size = scaled_size(start_index, sizes.total, sizes.max)
      let value = generator.generate(gen, here, size, sizes.max).value
      case
        body(
          value,
          RandomSource(seed_module.state(here), size, sizes.max),
          start_index,
        )
      {
        Continue ->
          run_random(
            gen,
            sizes,
            start_index + 1,
            remaining - 1,
            rest_seed,
            body,
          )
        Stop(text) -> Halted(text)
      }
    }
  }
}

fn scaled_size(index: Int, total: Int, max_size: Int) -> Int {
  case total <= 1 {
    True -> max_size
    False -> index * max_size / { total - 1 }
  }
}

// ---------- failure construction ----------

/// What the runner checks for every generated input, and how it turns a
/// failing (already shrunk) input into the report text.
type Check(a) {
  Check(
    regression_key: String,
    coverage_name: Option(String),
    holds: fn(a) -> Bool,
    report: fn(Failure(a)) -> String,
  )
}

/// A failing input after shrinking, with everything the report shows.
type Failure(a) {
  Failure(
    input: a,
    source: InputSource,
    run_index: Int,
    shrinks: Int,
    capped: Bool,
    coverage: coverage.Snapshot,
    /// Runner messages shown as footnotes, such as a regression file
    /// that could not be written.
    notes: List(String),
  )
}

/// Replay the regression entries, then drive the generated inputs, then
/// check coverage. Every runner that takes a generator goes through here.
fn run_check(
  cfg: Settings,
  test_name: String,
  gen: Generator(a),
  check: Check(a),
) -> Outcome {
  reset_state()
  let entries = load_regression_for(cfg, check.regression_key)
  use <- and_then(replay_regression(gen, check, entries))
  // The replayed entries are not runs: start counting coverage afresh.
  reset_state()
  use <- and_then(
    iterate_inputs(cfg, gen, fn(input, source, run_index) {
      check_step(cfg, gen, check, input, source, run_index)
    }),
  )
  coverage_outcome(test_name, check.coverage_name)
}

fn check_step(
  cfg: Settings,
  gen: Generator(a),
  check: Check(a),
  input: a,
  source: InputSource,
  run_index: Int,
) -> Step {
  // Annotations describe one run; coverage accumulates across runs.
  annotate.reset()
  coverage.count_run()
  case check.holds(input) {
    True -> Continue
    False -> {
      let notes =
        record_regression_for(cfg, check.regression_key, source, input)
      Stop(shrunk_failure(cfg, gen, check, input, source, run_index, notes))
    }
  }
}

fn and_then(outcome: Outcome, next: fn() -> Outcome) -> Outcome {
  case outcome {
    Done -> next()
    Halted(_) -> outcome
  }
}

fn finish(outcome: Outcome) -> Nil {
  case outcome {
    Done -> Nil
    Halted(text) -> panic_with(text)
  }
}

/// Shrink a failing input and render the report. The annotations are
/// rebuilt from one more run on the reported input so they describe that
/// input, not the shrink attempts.
fn shrunk_failure(
  cfg: Settings,
  gen: Generator(a),
  check: Check(a),
  input: a,
  source: InputSource,
  run_index: Int,
  notes: List(String),
) -> String {
  let snapshot = coverage.snapshot()
  let #(shrunk, shrinks, capped) =
    shrink_input(
      cfg,
      gen,
      fn(candidate) { !check.holds(candidate) },
      input,
      source,
    )
  annotate.reset()
  check.report(Failure(
    input: shrunk,
    source: source,
    run_index: run_index,
    shrinks: shrinks,
    capped: capped,
    coverage: snapshot,
    notes: notes,
  ))
}

fn forall_failure(
  cfg: Settings,
  test_name: String,
  property: fn(a) -> Bool,
  failure: Failure(a),
) -> String {
  let _ = property(failure.input)
  render_for(cfg, plain_report(cfg, test_name, failure))
}

/// The report for a failure of a plain property. The metamorphic report
/// starts from it and fills in the relation and the outputs.
fn plain_report(
  cfg: Settings,
  test_name: String,
  failure: Failure(a),
) -> FailureReport {
  FailureReport(
    mr_name: "(plain property)",
    test_name: test_name,
    config_seed: seed_module.state(cfg.seed),
    config_seed_original: seed_module.original_input(cfg.seed),
    runs_done: failure.run_index,
    runs_total: total_runs(cfg),
    shrinks_done: failure.shrinks,
    shrink_capped: failure.capped,
    morph_mode: None,
    relation_name: "",
    source_input: string.inspect(failure.input),
    followup_input: "",
    source_output: "",
    followup_output: "",
    input_source: failure.source,
    annotations: annotate.current_annotations(),
    footnotes: list.append(annotate.current_footnotes(), failure.notes),
    coverage_snapshot: Some(failure.coverage),
  )
}

type Evaluation(b) {
  Evaluation(followup_input: String, src_output: b, fol_output: b, holds: Bool)
}

fn evaluate_spec(
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  input: a,
) -> Evaluation(b) {
  let #(followup_input, src_output, rel) = case spec {
    PlainSpec(_name, t, r) -> #(t.apply(input), f(input), r)
    EquivariantSpec(_name, ti, to, r) -> #(
      ti.apply(input),
      to.apply(f(input)),
      r,
    )
  }
  let fol_output = f(followup_input)
  Evaluation(
    followup_input: string.inspect(followup_input),
    src_output: src_output,
    fol_output: fol_output,
    holds: rel.holds(src_output, fol_output),
  )
}

fn morph_mode_of(spec: MorphSpec(a, b)) -> MorphMode {
  case spec {
    PlainSpec(_, t, _) -> Plain(transform_name: t.name)
    EquivariantSpec(_, ti, to, _) ->
      Equivariant(input_transform_name: ti.name, output_transform_name: to.name)
  }
}

fn relation_name_of(spec: MorphSpec(a, b)) -> String {
  case spec {
    PlainSpec(_, _, r) -> r.name
    EquivariantSpec(_, _, _, r) -> r.name
  }
}

fn spec_name(spec: MorphSpec(a, b)) -> String {
  case spec {
    PlainSpec(name, _, _) -> name
    EquivariantSpec(name, _, _, _) -> name
  }
}

fn morph_failure(
  cfg: Settings,
  test_name: String,
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  failure: Failure(a),
) -> String {
  let evaluation = evaluate_spec(spec, f, failure.input)
  let report =
    FailureReport(
      ..plain_report(cfg, test_name, failure),
      mr_name: spec_name(spec),
      morph_mode: Some(morph_mode_of(spec)),
      relation_name: relation_name_of(spec),
      followup_input: evaluation.followup_input,
      source_output: string.inspect(evaluation.src_output),
      followup_output: string.inspect(evaluation.fol_output),
    )
  render_for(cfg, report)
}

fn morph_failure_static(
  test_name: String,
  spec: MorphSpec(a, b),
  input: a,
  evaluation: Evaluation(b),
) -> FailureReport {
  FailureReport(
    mr_name: spec_name(spec),
    test_name: test_name,
    config_seed: 0,
    config_seed_original: None,
    runs_done: 0,
    runs_total: 1,
    shrinks_done: 0,
    shrink_capped: False,
    morph_mode: Some(morph_mode_of(spec)),
    relation_name: relation_name_of(spec),
    source_input: string.inspect(input),
    followup_input: evaluation.followup_input,
    source_output: string.inspect(evaluation.src_output),
    followup_output: string.inspect(evaluation.fol_output),
    input_source: EdgeSource(0),
    annotations: annotate.current_annotations(),
    footnotes: annotate.current_footnotes(),
    coverage_snapshot: None,
  )
}

// ---------- shrinking ----------

/// Walk the failing input's shrink tree, keeping the first child that
/// still fails, until no child fails or the shrink limit is reached.
/// `fails` is the only thing the loop knows about the property.
fn shrink_input(
  cfg: Settings,
  gen: Generator(a),
  fails: fn(a) -> Bool,
  input: a,
  source: InputSource,
) -> #(a, Int, Bool) {
  case source {
    EdgeSource(_) -> #(input, 0, False)
    RandomSource(seed_value, size, max_size) -> {
      let initial_tree =
        generator.generate(gen, seed_module.seed(seed_value), size, max_size)
      shrink_loop(initial_tree, fails, input, cfg.shrink_limit, 0)
    }
  }
}

fn shrink_loop(
  current_tree: Tree(a),
  fails: fn(a) -> Bool,
  best: a,
  budget: Int,
  done: Int,
) -> #(a, Int, Bool) {
  case done >= budget {
    True -> #(best, done, True)
    False ->
      case
        tree.shrinks_find(current_tree.shrinks, fn(child: Tree(a)) {
          fails(child.value)
        })
      {
        Error(_) -> #(best, done, False)
        Ok(child) -> shrink_loop(child, fails, child.value, budget, done + 1)
      }
  }
}

// ---------- helpers ----------

fn reset_state() -> Nil {
  annotate.reset()
  coverage.reset()
}

fn coverage_outcome(test_name: String, morph_name: Option(String)) -> Outcome {
  let snap = coverage.snapshot()
  case coverage.first_shortfall(snap) {
    None -> Done
    Some(req) -> {
      let prefix = case morph_name {
        None -> "× property `" <> test_name <> "`"
        Some(name) ->
          "× metamorphic relation `" <> name <> "` (" <> test_name <> ")"
      }
      Halted(
        prefix
        <> " passed but coverage shortfall: label `"
        <> req.label
        <> "` hit "
        <> int.to_string(req.hits)
        <> "/"
        <> int.to_string(snap.total)
        <> " ("
        <> float.to_string(coverage.actual_pct(req.hits, snap.total))
        <> "%, target≥"
        <> float.to_string(coverage.target_pct_of(req, snap.total))
        <> "%)",
      )
    }
  }
}

fn panic_with(message: String) -> Nil {
  panic as message
}

// ---------- regression file ----------

fn load_regression_for(
  cfg: Settings,
  mr_name: String,
) -> List(regression.Entry) {
  case cfg.regression_file {
    None -> []
    Some(path) ->
      case simplifile.read(path) {
        Ok(content) ->
          regression.parse(content)
          |> list.filter(fn(entry: regression.Entry) {
            entry.mr_name == mr_name
          })
        Error(_) -> []
      }
  }
}

fn record_regression_for(
  cfg: Settings,
  mr_name: String,
  source: InputSource,
  input: a,
) -> List(String) {
  case cfg.regression_file {
    None -> []
    Some(path) -> {
      let edge_index = case source {
        EdgeSource(i) -> Some(i)
        RandomSource(..) -> None
      }
      let #(seed_value, size, max_size) = case source {
        EdgeSource(_) -> #(seed_module.state(cfg.seed), 0, cfg.max_size)
        RandomSource(s, sz, max) -> #(s, sz, max)
      }
      let run_index = case source {
        EdgeSource(i) -> i
        RandomSource(..) -> 0
      }
      let entry =
        regression.Entry(
          mr_name: mr_name,
          config_seed: seed_value,
          run_index: run_index,
          size: size,
          max_size: max_size,
          edge_index: edge_index,
          note: Some(string.inspect(input)),
          recorded: int.to_string(now_microseconds()),
        )
      case append_regression_entry(path, regression.render(entry)) {
        Ok(Nil) -> []
        Error(error) -> [
          "could not write the regression file "
          <> path
          <> ": "
          <> string.inspect(error),
        ]
      }
    }
  }
}

/// Append one rendered entry. A missing or empty file gets the version
/// header first; an existing file is appended to, not rewritten.
fn append_regression_entry(
  path: String,
  rendered: String,
) -> Result(Nil, simplifile.FileError) {
  case simplifile.file_info(path) {
    Ok(info) if info.size > 0 -> simplifile.append(path, "\n" <> rendered)
    _ ->
      simplifile.write(path, regression.version_header() <> "\n\n" <> rendered)
  }
}

fn replay_regression(
  gen: Generator(a),
  check: Check(a),
  entries: List(regression.Entry),
) -> Outcome {
  case entries {
    [] -> Done
    [entry, ..rest] -> {
      let value = reproduce_entry_value(gen, entry)
      case check.holds(value) {
        True -> replay_regression(gen, check, rest)
        False ->
          Halted(replay_failure_message(check.regression_key, entry, value))
      }
    }
  }
}

fn reproduce_entry_value(gen: Generator(a), entry: regression.Entry) -> a {
  let regenerate = fn() {
    generator.generate(
      gen,
      seed_module.seed(entry.config_seed),
      entry.size,
      entry.max_size,
    ).value
  }
  case entry.edge_index {
    Some(i) -> {
      // Edge replay: pick the i-th edge of the generator.
      case list.drop(generator.edges_of(gen), i) {
        [value, ..] -> value
        [] ->
          // Edge index drifted; fall back to generating with the
          // recorded seed so the runner still produces a value.
          regenerate()
      }
    }
    None ->
      // Random replay: same seed + size produces the same value.
      regenerate()
  }
}

fn replay_failure_message(
  mr_name: String,
  entry: regression.Entry,
  value: a,
) -> String {
  string.concat([
    "× regression replay for `",
    mr_name,
    "` failed\n  recorded:    ",
    entry.recorded,
    "\n  config_seed: ",
    int.to_string(entry.config_seed),
    "\n  run_index:   ",
    int.to_string(entry.run_index),
    "\n  size:        ",
    int.to_string(entry.size),
    "\n  max_size:    ",
    int.to_string(entry.max_size),
    "\n  reproduced input:\n    ",
    string.inspect(value),
    case entry.note {
      Some(n) -> "\n  note:\n    " <> n
      None -> ""
    },
  ])
}

@external(erlang, "metamon_ffi", "now_microseconds")
@external(javascript, "../../metamon_ffi.mjs", "now_microseconds")
fn now_microseconds() -> Int

/// The number of runs to target: `Config.runs` times the positive integer
/// in `METAMON_RUNS_MULTIPLIER`, when that variable is set. A nightly job
/// raises it to explore far more inputs than a pull request can afford,
/// without editing any test. Any other value is a mistake in the job, so it
/// stops the run instead of being ignored.
fn total_runs(cfg: Settings) -> Int {
  cfg.runs * runs_multiplier()
}

fn runs_multiplier() -> Int {
  case getenv("METAMON_RUNS_MULTIPLIER") {
    Error(Nil) -> 1
    Ok(value) ->
      case int.parse(string.trim(value)) {
        Ok(n) if n > 0 -> n
        _ ->
          panic as {
            "METAMON_RUNS_MULTIPLIER must be a positive integer (got \""
            <> value
            <> "\")"
          }
      }
  }
}

@external(erlang, "metamon_ffi", "getenv")
@external(javascript, "../../metamon_ffi.mjs", "getenv")
fn getenv(name: String) -> Result(String, Nil)
