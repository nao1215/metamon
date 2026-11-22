//// `forall_morph` and `forall_morphs` go through the same pipeline as
//// `forall`: regression replay and record, the coverage check, and
//// shrinking.

import gleam/option.{Some}
import gleam/string
import metamon
import metamon/coverage
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import simplifile
import test_helpers

const tmp_path: String = "/tmp/metamon_morph_pipeline_test.toml"

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  assert panicked
  message
}

fn ints() -> generator.Generator(Int) {
  generator.int(range.constant(0, 1000)) |> generator.no_edges
}

fn below_ten() -> metamon.Mr(Int, Int) {
  metamon.mr(
    name: "below_ten",
    transform: transform.new("identity", fn(value) { value }),
    relation: relation.new("source below ten", fn(source, _) { source < 10 }),
  )
}

fn seeded(value: Int) -> metamon.Config {
  metamon.Config(..metamon.default_config(), seed: Some(value))
}

pub fn forall_morph_shrinks_test() {
  let text =
    failure_text(fn() {
      metamon.forall_morph_with(seeded(42), ints(), below_ten(), fn(x) { x })
    })
  assert string.contains(text, "source input  (shrunk):\n    10\n")
}

pub fn forall_morph_records_and_replays_regressions_test() {
  let _ = simplifile.delete(tmp_path)
  let cfg = metamon.Config(..seeded(42), regression_file: Some(tmp_path))
  let _ =
    failure_text(fn() {
      metamon.forall_morph_with(cfg, ints(), below_ten(), fn(x) { x })
    })
  let assert Ok(content) = simplifile.read(tmp_path)
  assert string.contains(content, "mr          = \"below_ten\"")
  // A later run with another seed replays the recorded input first.
  let text =
    failure_text(fn() {
      metamon.forall_morph_with(
        metamon.Config(..seeded(1), regression_file: Some(tmp_path)),
        ints(),
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
      transform: transform.new("identity", fn(value) { value }),
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
