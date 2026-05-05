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

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import metamon/annotate
import metamon/config.{type Config}
import metamon/coverage
import metamon/generator.{type Generator}
import metamon/generator/seed.{type Seed} as seed_module
import metamon/generator/tree.{type Tree}
import metamon/internal/report.{
  type FailureReport, type InputSource, type MorphMode, EdgeSource, Equivariant,
  FailureReport, Plain, RandomSource,
}
import metamon/relation.{type Relation}
import metamon/transform.{type Transform}

/// Internal description of a metamorphic relation. Built from
/// `metamon.mr` and `metamon.mr_equivariant`.
pub type MorphSpec(a, b) {
  PlainSpec(name: String, transform: Transform(a), relation: Relation(b))
  EquivariantSpec(
    name: String,
    input_transform: Transform(a),
    output_transform: Transform(b),
    relation: Relation(b),
  )
}

/// Run a property test (no metamorphic transform).
pub fn run_forall(
  cfg: Config,
  test_name: String,
  gen: Generator(a),
  property: fn(a) -> Bool,
) -> Nil {
  reset_state()
  case
    iterate_inputs(cfg, gen, fn(input, source, run_index) {
      case property(input) {
        True -> Continue
        False ->
          Stop(forall_failure(
            cfg,
            test_name,
            gen,
            property,
            run_index,
            input,
            source,
          ))
      }
    })
  {
    Done -> finish_with_coverage_check(cfg, test_name, None)
    Halted(report_text) -> panic_with(report_text)
  }
}

/// Run a metamorphic relation against `f` for many inputs.
pub fn run_forall_morph(
  cfg: Config,
  test_name: String,
  gen: Generator(a),
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
) -> Nil {
  reset_state()
  case
    iterate_inputs(cfg, gen, fn(input, source, run_index) {
      let evaluation = evaluate_spec(spec, f, input)
      case evaluation.holds {
        True -> Continue
        False ->
          Stop(morph_failure(
            cfg,
            test_name,
            gen,
            spec,
            f,
            run_index,
            input,
            source,
            evaluation,
          ))
      }
    })
  {
    Done -> finish_with_coverage_check(cfg, test_name, Some(spec_name(spec)))
    Halted(report_text) -> panic_with(report_text)
  }
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
      let report =
        morph_failure_static(test_name, spec, input, evaluation, 0, 0)
      panic_with(report.render(report))
    }
  }
}

/// Run multiple metamorphic specs against the same generator + `f`.
/// Each spec is run independently; failures are collected and the
/// runner panics at the end if any spec failed.
pub fn run_forall_morphs(
  cfg: Config,
  test_name: String,
  gen: Generator(a),
  specs: List(MorphSpec(a, b)),
  f: fn(a) -> b,
) -> Nil {
  let collected =
    list.fold(specs, [], fn(reports, spec) {
      reset_state()
      let outcome =
        iterate_inputs(cfg, gen, fn(input, source, run_index) {
          let evaluation = evaluate_spec(spec, f, input)
          case evaluation.holds {
            True -> Continue
            False ->
              Stop(morph_failure(
                cfg,
                test_name,
                gen,
                spec,
                f,
                run_index,
                input,
                source,
                evaluation,
              ))
          }
        })
      case outcome {
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

type Step(a) {
  Continue
  Stop(report_text: String)
}

type Outcome {
  Done
  Halted(report_text: String)
}

fn iterate_inputs(
  cfg: Config,
  gen: Generator(a),
  body: fn(a, InputSource, Int) -> Step(a),
) -> Outcome {
  let edges = generator.edges_of(gen) |> take_first(config.max_edges(cfg))
  let edge_count = list.length(edges)
  let run_total = config.runs(cfg)
  case run_edges(edges, 0, body) {
    Halted(text) -> Halted(text)
    Done -> {
      let remaining = run_total - edge_count
      case remaining <= 0 {
        True -> Done
        False ->
          run_random(cfg, gen, edge_count, remaining, config.seed(cfg), body)
      }
    }
  }
}

fn run_edges(
  edges: List(a),
  index: Int,
  body: fn(a, InputSource, Int) -> Step(a),
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

fn run_random(
  cfg: Config,
  gen: Generator(a),
  start_index: Int,
  remaining: Int,
  s: Seed,
  body: fn(a, InputSource, Int) -> Step(a),
) -> Outcome {
  case remaining <= 0 {
    True -> Done
    False -> {
      let #(here, rest_seed) = seed_module.split(s)
      let size =
        scaled_size(start_index, config.runs(cfg), config.max_size(cfg))
      let value = generator.generate(gen, here, size).value
      case
        body(value, RandomSource(seed_module.state(here), size), start_index)
      {
        Continue ->
          run_random(cfg, gen, start_index + 1, remaining - 1, rest_seed, body)
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

fn forall_failure(
  cfg: Config,
  test_name: String,
  _gen: Generator(a),
  _property: fn(a) -> Bool,
  run_index: Int,
  input: a,
  source: InputSource,
) -> String {
  let report =
    FailureReport(
      mr_name: "(plain property)",
      test_name: test_name,
      config_seed: seed_module.state(config.seed(cfg)),
      runs_done: run_index,
      runs_total: config.runs(cfg),
      shrinks_done: 0,
      shrink_capped: False,
      morph_mode: None,
      relation_name: "",
      source_input: string.inspect(input),
      followup_input: "",
      source_output: "",
      followup_output: "",
      input_source: source,
      diff_enabled: False,
      annotations: annotate.current_annotations(),
      footnotes: annotate.current_footnotes(),
      coverage_snapshot: Some(coverage.snapshot()),
    )
  report.render(report)
}

type Evaluation(b) {
  Evaluation(followup_input: String, src_output: b, fol_output: b, holds: Bool)
}

fn evaluate_spec(
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  input: a,
) -> Evaluation(b) {
  case spec {
    PlainSpec(_name, t, r) -> {
      let fol_in = t.apply(input)
      let src_out = f(input)
      let fol_out = f(fol_in)
      Evaluation(
        followup_input: string.inspect(fol_in),
        src_output: src_out,
        fol_output: fol_out,
        holds: r.holds(src_out, fol_out),
      )
    }
    EquivariantSpec(_name, ti, to, r) -> {
      let fol_in = ti.apply(input)
      let raw_src_out = f(input)
      let src_out = to.apply(raw_src_out)
      let fol_out = f(fol_in)
      Evaluation(
        followup_input: string.inspect(fol_in),
        src_output: src_out,
        fol_output: fol_out,
        holds: r.holds(src_out, fol_out),
      )
    }
  }
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
  cfg: Config,
  test_name: String,
  gen: Generator(a),
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  run_index: Int,
  input: a,
  source: InputSource,
  evaluation: Evaluation(b),
) -> String {
  let #(shrunk_input, shrinks_count, capped) =
    shrink_morph_input(cfg, gen, spec, f, input, source)
  let final_eval = evaluate_spec(spec, f, shrunk_input)
  let report =
    FailureReport(
      mr_name: spec_name(spec),
      test_name: test_name,
      config_seed: seed_module.state(config.seed(cfg)),
      runs_done: run_index,
      runs_total: config.runs(cfg),
      shrinks_done: shrinks_count,
      shrink_capped: capped,
      morph_mode: Some(morph_mode_of(spec)),
      relation_name: relation_name_of(spec),
      source_input: string.inspect(shrunk_input),
      followup_input: final_eval.followup_input,
      source_output: string.inspect(final_eval.src_output),
      followup_output: string.inspect(final_eval.fol_output),
      input_source: source,
      diff_enabled: config.diff_enabled(cfg),
      annotations: annotate.current_annotations(),
      footnotes: annotate.current_footnotes(),
      coverage_snapshot: Some(coverage.snapshot()),
    )
  // Discard the unused evaluation argument — kept in the signature so
  // future shrinks can reuse the original failing evaluation if we
  // decide to short-circuit small inputs.
  let _ = evaluation
  report.render(report)
}

fn morph_failure_static(
  test_name: String,
  spec: MorphSpec(a, b),
  input: a,
  evaluation: Evaluation(b),
  run_index: Int,
  config_seed_value: Int,
) -> FailureReport {
  FailureReport(
    mr_name: spec_name(spec),
    test_name: test_name,
    config_seed: config_seed_value,
    runs_done: run_index,
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
    diff_enabled: True,
    annotations: annotate.current_annotations(),
    footnotes: annotate.current_footnotes(),
    coverage_snapshot: None,
  )
}

// ---------- shrinking ----------

fn shrink_morph_input(
  cfg: Config,
  gen: Generator(a),
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  current: a,
  source: InputSource,
) -> #(a, Int, Bool) {
  case source {
    EdgeSource(_) -> #(current, 0, False)
    RandomSource(seed_value, size) -> {
      let initial_tree =
        generator.generate(gen, seed_module.seed(seed_value), size)
      shrink_loop(initial_tree, spec, f, current, config.shrink_limit(cfg), 0)
    }
  }
}

fn shrink_loop(
  current_tree: Tree(a),
  spec: MorphSpec(a, b),
  f: fn(a) -> b,
  best: a,
  budget: Int,
  done: Int,
) -> #(a, Int, Bool) {
  case done >= budget {
    True -> #(best, done, True)
    False ->
      case
        tree.shrinks_find(current_tree.shrinks, fn(child: Tree(a)) {
          let evaluation = evaluate_spec(spec, f, child.value)
          !evaluation.holds
        })
      {
        Error(_) -> #(best, done, False)
        Ok(child) -> shrink_loop(child, spec, f, child.value, budget, done + 1)
      }
  }
}

// ---------- helpers ----------

fn reset_state() -> Nil {
  annotate.reset()
  coverage.reset()
}

fn finish_with_coverage_check(
  _cfg: Config,
  test_name: String,
  morph_name: Option(String),
) -> Nil {
  let snap = coverage.snapshot()
  case coverage.first_shortfall(snap) {
    None -> Nil
    Some(req) -> {
      let prefix = case morph_name {
        None -> "× property `" <> test_name <> "`"
        Some(name) ->
          "× metamorphic relation `" <> name <> "` (" <> test_name <> ")"
      }
      let message =
        prefix
        <> " passed but coverage shortfall: label `"
        <> req.label
        <> "` hit "
        <> int.to_string(req.hits)
        <> "/"
        <> int.to_string(snap.total)
        <> " ("
        <> float_to_string(coverage.actual_pct(req.hits, snap.total))
        <> "%, target≥"
        <> float_to_string(req.target_pct)
        <> "%)"
      panic_with(message)
    }
  }
}

fn panic_with(message: String) -> Nil {
  panic as message
}

fn take_first(items: List(a), n: Int) -> List(a) {
  case n, items {
    n, _ if n <= 0 -> []
    _, [] -> []
    n, [first, ..rest] -> [first, ..take_first(rest, n - 1)]
  }
}

@external(erlang, "erlang", "float_to_binary")
@external(javascript, "../../metamon_ffi.mjs", "float_to_string")
fn float_to_string(value: Float) -> String
