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
import test_helpers

fn ints() -> generator.Generator(Int) {
  generator.int(generator.range(0, 1000)) |> generator.no_edges
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

pub fn shrinking_keeps_the_original_failure_test() {
  // Two different failures: "large" from 100 up, "odd" for odd values
  // from 11 to 99. Shrinking may only move to inputs that fail the same
  // way, so the report never mixes one failure's input with the other.
  list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(seed_value) {
    let #(panicked, text) =
      test_helpers.capture_panic(fn() {
        metamon.forall_with(seeded(seed_value), ints(), two_failures)
      })
    assert panicked
    let large = string.contains(text, "panic message:\n    large\n")
    let odd = string.contains(text, "panic message:\n    odd\n")
    assert large || odd
    assert !large || shrunk_to(text, "100")
    assert !odd || shrunk_to(text, "11")
  })
}

fn two_failures(n: Int) -> Nil {
  case n >= 100, n >= 10 && n % 2 == 1 {
    // nolint: avoid_panic
    True, _ -> panic as "large"
    // nolint: avoid_panic
    False, True -> panic as "odd"
    False, False -> Nil
  }
}

pub fn the_message_belongs_to_the_reported_input_test() {
  // Each input panics with its own value, so shrinking keeps the first
  // failing input and the report shows that input's message.
  let text =
    failure_text(fn(n) {
      case n >= 10 {
        // nolint: avoid_panic
        True -> panic as { "got " <> int.to_string(n) }
        False -> Nil
      }
    })
  let assert Ok(#(_, rest)) =
    string.split_once(text, "source input  (shrunk):\n    ")
  let assert Ok(#(input, _)) = string.split_once(rest, "\n")
  assert string.contains(text, "panic message:\n    got " <> input <> "\n")
}

fn panics_from_ten(n: Int) -> Int {
  case n >= 10 {
    // nolint: avoid_panic
    True -> panic as "f gave up"
    False -> n
  }
}

pub fn a_panicking_function_fails_the_morph_and_is_shrunk_test() {
  let identity = metamon.Transform(name: "identity", apply: fn(n) { n })
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_morph_with(
        seeded(42),
        ints(),
        [
          metamon.invariant_under(name: "first", under: identity),
          metamon.invariant_under(name: "second", under: identity),
        ],
        panics_from_ten,
      )
    })
  assert panicked
  // Both morphs are checked and reported.
  assert string.contains(text, "`first` failed")
  assert string.contains(text, "`second` failed")
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:\n    f gave up")
}

pub fn a_panicking_transform_fails_the_morph_test() {
  let explode =
    metamon.Transform(name: "explode", apply: fn(n) {
      case n >= 10 {
        // nolint: avoid_panic
        True -> panic as "transform gave up"
        False -> n
      }
    })
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_morph_with(
        seeded(42),
        ints(),
        [metamon.invariant_under(name: "explode", under: explode)],
        fn(n) { n },
      )
    })
  assert panicked
  assert shrunk_to(text, "10")
  assert string.contains(text, "panic message:\n    transform gave up")
}

pub fn assert_morph_reports_a_panicking_function_test() {
  let identity = metamon.Transform(name: "identity", apply: fn(n) { n })
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.assert_morph(
        12,
        metamon.invariant_under(name: "id", under: identity),
        panics_from_ten,
      )
    })
  assert panicked
  assert string.contains(text, "× metamorphic relation `id` failed")
  assert string.contains(text, "panic message:\n    f gave up")
}

pub fn round_trip_reproduce_line_checks_the_round_trip_test() {
  let #(_, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_round_trip_with(
        config: seeded(42),
        generator: ints(),
        name: "broken",
        encode: fn(n) { n },
        decode: fn(_) { Error(Nil) },
      )
    })
  assert string.contains(text, "assert decode(encode(input)) == Ok(input)")
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
  assert string.contains(text, "returned a value other than the input")
  assert string.contains(text, "- decode(encode(input)): Ok(11)")
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
