//// The coverage percentage is hits over runs, however many coverage
//// calls one run makes.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import metamon/internal/coverage
import simplifile
import test_helpers

const tmp_path: String = "/tmp/metamon_coverage_denominator_test.toml"

pub fn two_covers_per_run_count_each_run_once_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(_) {
    metamon.cover(at_least: 60.0, label: "a", when: True)
    metamon.cover(at_least: 60.0, label: "b", when: True)
  })
}

pub fn classify_does_not_dilute_cover_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(n) {
    metamon.cover(at_least: 100.0, label: "always", when: True)
    metamon.classify(label: "even", when: n % 2 == 0)
    metamon.classify(label: "small", when: n < 10)
  })
}

pub fn classify_counts_appear_in_the_failure_report_test() {
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), seed: Some(1)),
        generator.int(range.constant(0, 100)) |> generator.no_edges,
        fn(n) {
          metamon.classify(label: "any", when: True)
          assert n < 50
        },
      )
    })
  assert panicked
  // The runs up to and including the first failing one hit the label.
  assert string.contains(text, "  coverage:\n    any: ")
}

pub fn every_run_count_keeps_full_coverage_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 20),
    generator.int(range.constant(1, 300)),
    fn(runs) {
      let #(panicked, _) =
        test_helpers.capture_panic(fn() {
          metamon.forall_with(
            metamon.Config(..metamon.default_config(), runs: runs),
            generator.int(range.constant(0, 9)),
            fn(_) {
              metamon.cover(at_least: 100.0, label: "x", when: True)
              metamon.cover(at_least: 100.0, label: "y", when: True)
              metamon.cover(at_least: 100.0, label: "z", when: True)
            },
          )
        })
      assert !panicked
    },
  )
}

pub fn shortfall_reports_runs_as_the_denominator_test() {
  count_reset()
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), runs: 40),
        generator.int(range.constant(0, 9)) |> generator.no_edges,
        fn(_) {
          count_bump()
          metamon.classify(label: "noise", when: True)
          metamon.cover(at_least: 50.0, label: "never", when: False)
        },
      )
    })
  assert panicked
  assert string.contains(text, "hit 0/" <> int.to_string(count_get()) <> " ")
}

pub fn regression_replay_does_not_count_towards_coverage_test() {
  let _ = simplifile.delete(tmp_path)
  let cfg =
    metamon.Config(
      ..metamon.default_config(),
      seed: Some(9),
      runs: 10,
      regression_file: Some(tmp_path),
    )
  let gen = generator.int(range.constant(0, 9)) |> generator.no_edges
  // Count the runs (METAMON_RUNS_MULTIPLIER may scale them).
  count_reset()
  metamon.forall_with(cfg, gen, fn(_) { count_bump() })
  let runs = count_get()
  // Record one entry with a failing run.
  let _ =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(cfg, gen, fn(_) { test_helpers.fail() })
    })
  // The replayed entry runs the property once more, but only the runs
  // count: the coverage state left by the run holds `runs` runs and hits.
  metamon.forall_with(cfg, gen, fn(_) {
    metamon.classify(label: "hit", when: True)
  })
  let _ = simplifile.delete(tmp_path)
  let snapshot = coverage.snapshot()
  assert snapshot.total == runs
  assert dict.get(snapshot.counts, "hit") == Ok(runs)
}

pub fn a_label_counts_once_per_run_test() {
  // Calling cover twice in one run must not double the hits: about half
  // the runs draw 0, which is short of 60%.
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), seed: Some(4)),
        generator.int(range.constant(0, 1)),
        fn(n) {
          metamon.cover(at_least: 60.0, label: "zero", when: n == 0)
          metamon.cover(at_least: 60.0, label: "zero", when: n == 0)
        },
      )
    })
  assert panicked
  assert string.contains(text, "label `zero`")
}

pub fn hits_never_exceed_runs_test() {
  count_reset()
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 30),
    generator.list_of(generator.return(0), range.constant(1, 5)),
    fn(xs) {
      count_bump()
      list.each(xs, fn(x) {
        metamon.classify(label: "zero", when: x == 0)
        metamon.cover(at_least: 100.0, label: "many", when: x == 0)
      })
    },
  )
  let snapshot = coverage.snapshot()
  assert snapshot.total == count_get()
  assert dict.get(snapshot.counts, "zero") == Ok(count_get())
  assert dict.get(snapshot.counts, "many") == Ok(count_get())
}

@external(erlang, "metamon_env_test_ffi", "count_reset")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_reset")
fn count_reset() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_bump")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_bump")
fn count_bump() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_get")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_get")
fn count_get() -> Int
