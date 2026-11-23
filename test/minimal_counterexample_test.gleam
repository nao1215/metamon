//// A failing input shrinks to the smallest counterexample, whether the
//// run found it among the edge values or the random inputs, as in
//// QuickCheck and Hypothesis.

import gleam/list
import gleam/option.{None, Some}
import gleam/string
import metamon
import metamon/generator
import test_helpers

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  assert panicked
  message
}

fn seeded(value: Int) -> metamon.Config {
  metamon.Config(..metamon.default_config(), seed: Some(value))
}

fn shrunk_input(text: String) -> String {
  case string.split_once(text, "source input  (shrunk):\n    ") {
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\n") {
        Ok(#(line, _)) -> line
        Error(Nil) -> rest
      }
    Error(Nil) -> text
  }
}

fn shrinks_to(
  generator: generator.Generator(a),
  property: fn(a) -> Nil,
  seed: Int,
) -> String {
  failure_text(fn() { metamon.forall_with(seeded(seed), generator, property) })
  |> shrunk_input
}

pub fn a_failing_int_edge_shrinks_test() {
  // 100 is an edge value of the range and fails first.
  let ints = generator.int(generator.range(from: 0, to: 100))
  assert shrinks_to(
      ints,
      fn(n) {
        assert n < 50
      },
      1,
    )
    == "50"
}

pub fn a_failing_list_edge_shrinks_test() {
  let lists =
    generator.list_of(
      generator.int(generator.range(from: 0, to: 10)),
      length: generator.range(from: 0, to: 10),
    )
  let property = fn(items) {
    assert list.length(items) < 2
  }
  assert shrinks_to(lists, property, 2) == "[0, 0]"
}

pub fn a_failing_string_edge_shrinks_test() {
  let strings =
    generator.string(
      of: generator.Ascii,
      length: generator.range(from: 0, to: 20),
    )
  let property = fn(text) {
    assert !string.contains(text, "e")
  }
  assert shrinks_to(strings, property, 2) == "\"e\""
}

pub fn a_failing_example_is_reported_as_given_test() {
  // Explicit examples are the caller's own inputs and stay as they are.
  let ints =
    generator.int(generator.range(from: 0, to: 100))
    |> generator.no_edges
    |> generator.with_examples([77])
  assert shrinks_to(
      ints,
      fn(n) {
        assert n < 50
      },
      1,
    )
    == "77"
}

pub fn a_float_shrinks_toward_the_boundary_test() {
  // The upper bound 1000.0 also fails, but it is not the smallest
  // failing value.
  let floats = generator.float(from: -1000.0, to: 1000.0)
  list.each([1, 2, 3, 4, 5], fn(seed) {
    assert shrinks_to(
        floats,
        fn(x) {
          assert x <. 500.0
        },
        seed,
      )
      == string.inspect(500.0)
  })
}

pub fn a_float_shrinks_toward_zero_test() {
  let floats = generator.float(from: -1000.0, to: 1000.0) |> generator.no_edges
  assert shrinks_to(floats, fn(_) { test_helpers.fail() }, 3)
    == string.inspect(0.0)
}

pub fn a_unicode_character_shrinks_to_the_first_non_ascii_character_test() {
  // The smallest code point that UTF-8 encodes in two bytes is U+0080.
  let characters = generator.character(of: generator.Unicode)
  let property = fn(text) {
    assert string.byte_size(text) == 1
  }
  list.each([1, 2, 3], fn(seed) {
    assert shrinks_to(characters, property, seed) == "\"\\u{0080}\""
    assert shrinks_to(characters |> generator.no_edges, property, seed)
      == "\"\\u{0080}\""
  })
}

pub fn a_bool_shrinks_to_false_test() {
  let pairs =
    generator.tuple2(
      generator.bool(),
      generator.int(generator.range(from: 0, to: 10)),
    )
    |> generator.no_edges
  let property = fn(pair: #(Bool, Int)) {
    assert pair.1 < 5
  }
  list.each([1, 2, 3, 4], fn(seed) {
    assert shrinks_to(pairs, property, seed) == "#(False, 5)"
  })
}

pub fn an_option_shrinks_to_none_test() {
  let options =
    generator.option_of(generator.int(generator.range(from: 0, to: 10)))
    |> generator.no_edges
  list.each([1, 2, 3, 4], fn(seed) {
    assert shrinks_to(options, fn(_) { test_helpers.fail() }, seed) == "None"
  })
  let property = fn(option) {
    assert option == None
  }
  assert shrinks_to(options, property, 2) == "Some(0)"
}

pub fn a_negative_zero_edge_shrinks_without_hanging_test() {
  // On Erlang -0.0 differs from 0.0, so shrinking it must not loop.
  let floats = generator.float(from: -0.0, to: 1.0)
  let text =
    failure_text(fn() {
      metamon.forall_with(seeded(1), floats, fn(_) { test_helpers.fail() })
    })
  assert string.contains(text, "shrinks:")
}

pub fn a_float_in_a_negative_range_shrinks_to_a_whole_number_test() {
  // The origin is the lower bound -10.5, so whole numbers are taken
  // toward it: -2.9 tries -3.0, which reaches the boundary exactly.
  let floats = generator.float(from: -10.5, to: -2.0) |> generator.no_edges
  let property = fn(x) {
    assert x <. -3.0
  }
  list.each([1, 2, 3, 4], fn(seed) {
    assert shrinks_to(floats, property, seed) == string.inspect(-3.0)
  })
}
