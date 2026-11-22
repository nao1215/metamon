//// The coverage percentage is hits over runs, however many coverage
//// calls one run makes.

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
    metamon.default_config() |> metamon.with_runs_or_panic(20),
    generator.int(range.constant(1, 300)),
    fn(runs) {
      let #(panicked, _) =
        capture_panic(fn() {
          metamon.forall_with(
            metamon.default_config() |> metamon.with_runs_or_panic(runs),
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
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(
        metamon.default_config() |> metamon.with_runs_or_panic(40),
        generator.int(range.constant(0, 9)) |> generator.no_edges,
        fn(_) {
          coverage.classify("noise", True)
          coverage.cover(50.0, "never", False)
          True
        },
      )
    })
  assert panicked
  assert string.contains(text, "hit 0/40 ")
}

pub fn regression_replay_does_not_count_towards_coverage_test() {
  let _ = simplifile.delete(tmp_path)
  let cfg =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(9))
    |> metamon.with_runs_or_panic(10)
    |> metamon.with_regression_file_or_panic(tmp_path)
  let gen = generator.int(range.constant(0, 9)) |> generator.no_edges
  // Record one entry with a failing run.
  let _ = capture_panic(fn() { metamon.forall_with(cfg, gen, fn(_) { False }) })
  // The replayed entry runs the property once more, but only the ten
  // runs count, so eleven hits are out of reach.
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(cfg, gen, fn(_) {
        coverage.cover_at_least(11, "hit", True)
        True
      })
    })
  let _ = simplifile.delete(tmp_path)
  assert panicked
  assert string.contains(text, "hit 10/10 ")
}
