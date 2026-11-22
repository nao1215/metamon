//// `forall_morphs` and `forall_morph_n` go through the same pipeline as
//// `forall_morph`: regression replay and record, the coverage check,
//// and shrinking.

import gleam/string
import metamon
import metamon/coverage
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import simplifile

const tmp_path: String = "/tmp/metamon_morph_pipeline_test.toml"

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = capture_panic(thunk)
  assert panicked
  message
}

fn ints() -> generator.Generator(Int) {
  generator.int(range.constant(0, 1000)) |> generator.no_edges
}

fn below_ten() -> relation.RelationN(Int) {
  relation.n_new("below_ten", fn(outputs) {
    case outputs {
      [first, ..] -> first < 10
      [] -> True
    }
  })
}

fn seeded(value: Int) -> metamon.Config {
  metamon.default_config() |> metamon.with_seed(metamon.seed(value))
}

pub fn forall_morph_n_shrinks_test() {
  let text =
    failure_text(fn() {
      metamon.forall_morph_n_with(
        seeded(42),
        ints(),
        [transform.identity()],
        below_ten(),
        fn(x) { x },
      )
    })
  assert string.contains(text, "source input:\n    10\n")
}

pub fn forall_morph_n_records_and_replays_regressions_test() {
  let _ = simplifile.delete(tmp_path)
  let cfg = seeded(42) |> metamon.with_regression_file_or_panic(tmp_path)
  let _ =
    failure_text(fn() {
      metamon.forall_morph_n_with(
        cfg,
        ints(),
        [transform.identity()],
        below_ten(),
        fn(x) { x },
      )
    })
  let assert Ok(content) = simplifile.read(tmp_path)
  assert string.contains(content, "mr          = \"below_ten\"")
  // A later run with another seed replays the recorded input first.
  let text =
    failure_text(fn() {
      metamon.forall_morph_n_with(
        seeded(1) |> metamon.with_regression_file_or_panic(tmp_path),
        ints(),
        [transform.identity()],
        below_ten(),
        fn(x) { x },
      )
    })
  assert string.contains(text, "regression replay for `below_ten`")
  let _ = simplifile.delete(tmp_path)
  Nil
}

pub fn forall_morphs_checks_coverage_test() {
  let never_hit =
    metamon.mr(
      name: "identity_under_identity",
      transform: transform.identity(),
      relation: relation.equal(),
    )
  let text =
    failure_text(fn() {
      metamon.forall_morphs(ints(), [never_hit], fn(x) {
        coverage.cover(50.0, "never", False)
        x
      })
    })
  assert string.contains(text, "coverage shortfall: label `never`")
}
