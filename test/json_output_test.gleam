//// Failure-report JSON output. The runner emits a single-line JSON
//// object instead of the human-readable text when configured with
//// `metamon.Config(..metamon.default_config(), output: metamon.Json)`.

import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range
import test_helpers

pub fn json_output_is_single_line_object_test() {
  let cfg = metamon.Config(..metamon.default_config(), output: metamon.Json)
  let outcome =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(cfg, generator.int(range.constant(0, 10)), fn(_n) {
        test_helpers.fail()
      })
    })
  should.equal(outcome.0, True)
  // Has to start with `{` and end with `}` (JSON object).
  let trimmed = string.trim(outcome.1)
  should.be_true(string.starts_with(trimmed, "{"))
  should.be_true(string.ends_with(trimmed, "}"))
  // Must contain stable schema fields.
  should.be_true(string.contains(trimmed, "\"mr_name\""))
  should.be_true(string.contains(trimmed, "\"runs_done\""))
  should.be_true(string.contains(trimmed, "\"shrinks_done\""))
  should.be_true(string.contains(trimmed, "\"source\""))
  should.be_true(string.contains(trimmed, "\"morph_mode\""))
  // No newline characters: it's a single line.
  should.be_false(string.contains(trimmed, "\n"))
}

pub fn json_output_for_morph_failure_test() {
  let increment = metamon.Transform("+1", fn(n: Int) { n + 1 })
  let bad_mr =
    metamon.Morph(
      name: "false_invariant",
      transform: increment,
      relation: metamon.equal(),
    )
  let cfg = metamon.Config(..metamon.default_config(), output: metamon.Json)
  let outcome =
    test_helpers.capture_panic(fn() {
      metamon.forall_morph_with(
        cfg,
        generator.int(range.constant(1, 10)),
        [bad_mr],
        fn(n) { n },
      )
    })
  should.equal(outcome.0, True)
  // The JSON must report the MR name and the transform name.
  // Plain MR uses "transform"; Equivariant uses "input_transform" /
  // "output_transform".
  should.be_true(string.contains(outcome.1, "\"false_invariant\""))
  should.be_true(string.contains(outcome.1, "\"transform\":\"+1\""))
}

pub fn text_output_is_default_test() {
  let outcome =
    test_helpers.capture_panic(fn() {
      metamon.forall(generator.int(range.constant(0, 10)), fn(_n) {
        test_helpers.fail()
      })
    })
  should.equal(outcome.0, True)
  // Text starts with the "× ..." header, not "{".
  should.be_true(string.starts_with(outcome.1, "× "))
}
