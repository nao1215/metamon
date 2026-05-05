//// Failure-report JSON output. The runner emits a single-line JSON
//// object instead of the human-readable text when configured with
//// `metamon.with_output_format(metamon.Json)`.

import gleam/string
import gleeunit/should
import metamon
import metamon/config
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

pub fn json_output_is_single_line_object_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  let outcome =
    capture_panic(fn() {
      metamon.forall_with(cfg, generator.int(range.constant(0, 10)), fn(_n) {
        False
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
  let increment = transform.new("+1", fn(n: Int) { n + 1 })
  let bad_mr =
    metamon.mr(
      name: "false_invariant",
      transform: increment,
      relation: relation.equal(),
    )
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  let outcome =
    capture_panic(fn() {
      metamon.forall_morph_with(
        cfg,
        generator.int(range.constant(1, 10)),
        bad_mr,
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
    capture_panic(fn() {
      metamon.forall(generator.int(range.constant(0, 10)), fn(_n) { False })
    })
  should.equal(outcome.0, True)
  // Text starts with the "× ..." header, not "{".
  should.be_true(string.starts_with(outcome.1, "× "))
}
