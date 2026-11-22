//// The coverage percentage is hits over runs, however many coverage
//// calls one run makes.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/coverage
import metamon/generator
import metamon/generator/range
import simplifile

const tmp_path: String = "/tmp/metamon_coverage_denominator_test.toml"

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

pub fn two_covers_per_run_count_each_run_once_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(_) {
    coverage.cover(60.0, "a", True)
    coverage.cover(60.0, "b", True)
    True
  })
}

pub fn classify_and_collect_do_not_dilute_cover_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(n) {
    coverage.cover(100.0, "always", True)
    coverage.classify("even", n % 2 == 0)
    coverage.collect(n % 3, fn(r) { string.inspect(r) })
    True
  })
}

pub fn every_run_count_keeps_full_coverage_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 20),
    generator.int(range.constant(1, 300)),
    fn(runs) {
      let #(panicked, _) =
        capture_panic(fn() {
          metamon.forall_with(
            metamon.Config(..metamon.default_config(), runs: runs),
            generator.int(range.constant(0, 9)),
            fn(_) {
              coverage.cover(100.0, "x", True)
              coverage.cover(100.0, "y", True)
              coverage.cover_at_least(runs, "z", True)
              True
            },
          )
        })
      !panicked
    },
  )
}

pub fn shortfall_reports_runs_as_the_denominator_test() {
  count_reset()
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), runs: 40),
        generator.int(range.constant(0, 9)) |> generator.no_edges,
        fn(_) {
          count_bump()
          coverage.classify("noise", True)
          coverage.cover(50.0, "never", False)
          True
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
  metamon.forall_with(cfg, gen, fn(_) {
    count_bump()
    True
  })
  let runs = count_get()
  // Record one entry with a failing run.
  let _ = capture_panic(fn() { metamon.forall_with(cfg, gen, fn(_) { False }) })
  // The replayed entry runs the property once more, but only the runs
  // count, so runs + 1 hits are out of reach.
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(cfg, gen, fn(_) {
        coverage.cover_at_least(runs + 1, "hit", True)
        True
      })
    })
  let _ = simplifile.delete(tmp_path)
  assert panicked
  let runs = int.to_string(runs)
  assert string.contains(text, "hit " <> runs <> "/" <> runs <> " ")
}

pub fn a_label_counts_once_per_run_test() {
  // Calling cover twice in one run must not double the hits: about half
  // the runs draw 0, which is short of 60%.
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), seed: Some(4)),
        generator.int(range.constant(0, 1)),
        fn(n) {
          coverage.cover(60.0, "zero", n == 0)
          coverage.cover(60.0, "zero", n == 0)
          True
        },
      )
    })
  assert panicked
  assert string.contains(text, "label `zero`")
}

pub fn hits_never_exceed_runs_test() {
  count_reset()
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..metamon.default_config(), runs: 30),
        generator.list_of(generator.return(0), range.constant(1, 5)),
        fn(xs) {
          count_bump()
          list.each(xs, fn(x) {
            coverage.classify("zero", x == 0)
            coverage.cover_at_least(1000, "many", x == 0)
          })
          True
        },
      )
    })
  assert panicked
  let runs = int.to_string(count_get())
  assert string.contains(text, "hit " <> runs <> "/" <> runs <> " ")
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
