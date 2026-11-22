//// A property fails when it panics: `assert`, `let assert`, `panic`, or
//// an error raised outside Gleam. The runner catches the panic, shrinks
//// the input to a smaller one that still panics, and reports the panic
//// message of the reported input.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import test_helpers

fn ints() -> generator.Generator(Int) {
  generator.int(range.constant(0, 1000)) |> generator.no_edges
}

fn seeded(value: Int) -> metamon.Config {
  metamon.Config(..metamon.default_config(), seed: Some(value))
}

fn failure_text(property: fn(Int) -> Nil) -> String {
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(seeded(42), ints(), property)
    })
  assert panicked
  text
}

fn shrunk_to(text: String, value: String) -> Bool {
  string.contains(text, "source input  (shrunk):\n    " <> value <> "\n")
}

@external(erlang, "metamon_env_test_ffi", "raise_foreign_error")
@external(javascript, "./metamon_env_test_ffi.mjs", "raise_foreign_error")
fn raise_foreign_error() -> Nil

pub fn passing_property_returns_nil_test() {
  metamon.forall(ints(), fn(n) {
    assert n >= 0
  })
}

pub fn failing_assert_is_shrunk_test() {
  let text =
    failure_text(fn(n) {
      assert n < 10
    })
  assert string.contains(text, "× property failed")
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:")
}

pub fn failing_let_assert_is_shrunk_test() {
  let text =
    failure_text(fn(n) {
      let assert [] = list.filter([n], fn(x) { x >= 10 }) as "n is at least 10"
      Nil
    })
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:\n    n is at least 10")
}

pub fn panic_is_shrunk_test() {
  let text =
    failure_text(fn(n) {
      case n >= 10 {
        // nolint: avoid_panic
        True -> panic as "too large"
        False -> Nil
      }
    })
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:\n    too large")
}

pub fn the_message_belongs_to_the_reported_input_test() {
  // Each input panics with its own value, so a message from a shrink
  // attempt or from the first failing input would show another number.
  let text =
    failure_text(fn(n) {
      case n >= 10 {
        // nolint: avoid_panic
        True -> panic as { "got " <> int.to_string(n) }
        False -> Nil
      }
    })
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:\n    got 10\n")
}

pub fn foreign_error_fails_the_property_test() {
  let text =
    failure_text(fn(n) {
      case n >= 10 {
        True -> raise_foreign_error()
        False -> Nil
      }
    })
  assert shrunk_to(text, "10")
  assert string.contains(text, "badarg")
}

pub fn json_report_carries_the_panic_message_test() {
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(
        metamon.Config(..seeded(42), output: metamon.Json),
        ints(),
        fn(n) {
          case n >= 10 {
            // nolint: avoid_panic
            True -> panic as "too large"
            False -> Nil
          }
        },
      )
    })
  assert panicked
  assert string.contains(text, "\"panic_message\":\"too large\"")
  assert string.contains(text, "\"source_input\":\"10\"")
}

pub fn round_trip_reports_the_decoded_value_test() {
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_round_trip_with(
        config: seeded(42),
        generator: ints(),
        name: "off_by_one",
        encode: fn(n) { n },
        decode: fn(n) {
          case n >= 10 {
            True -> Ok(n + 1)
            False -> Ok(n)
          }
        },
      )
    })
  assert panicked
  assert shrunk_to(text, "10")
  assert string.contains(text, "returned Ok(11), which is not the input")
}

pub fn round_trip_catches_a_panicking_decoder_test() {
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_round_trip_with(
        config: seeded(42),
        generator: ints(),
        name: "panicking_decoder",
        encode: fn(n) { n },
        decode: fn(n) {
          case n >= 10 {
            // nolint: avoid_panic
            True -> panic as "decoder gave up"
            False -> Ok(n)
          }
        },
      )
    })
  assert panicked
  assert string.contains(text, "round_trip[panicking_decoder]")
  assert shrunk_to(text, "10")
  assert string.contains(text, "decoder gave up")
}
