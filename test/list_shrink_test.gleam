//// List generators: shrinking keeps going after a drop, never goes
//// below the range's minimum length, long lists do not exhaust the
//// stack, and `non_empty_list_of` works at every size.

import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import test_helpers

fn shrunk_input(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  assert panicked
  let assert Ok(#(_, rest)) =
    string.split_once(message, "source input  (shrunk):\n    ")
  let assert Ok(#(input, _)) = string.split_once(rest, "\n")
  input
}

fn seeded(value: Int) -> metamon.Config {
  metamon.Config(..metamon.default_config(), seed: Some(value))
}

fn digits(len: range.Range) -> generator.Generator(List(Int)) {
  generator.list_of(generator.int(range.constant(0, 9)), len)
  |> generator.no_edges
}

pub fn list_shrinks_to_the_shortest_failing_length_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 20),
    generator.int(range.constant(1, 100_000)),
    fn(seed_value) {
      let input =
        shrunk_input(fn() {
          metamon.forall_with(
            seeded(seed_value),
            digits(range.constant(0, 20)),
            fn(xs) {
              assert list.length(xs) < 3
            },
          )
        })
      assert input == "[0, 0, 0]"
    },
  )
}

pub fn list_shrinks_both_length_and_elements_test() {
  let input =
    shrunk_input(fn() {
      metamon.forall_with(seeded(42), digits(range.constant(0, 30)), fn(xs) {
        assert !list.contains(xs, 7)
      })
    })
  assert input == "[7]"
}

pub fn list_shrinking_keeps_the_minimum_length_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 20),
    generator.int(range.constant(1, 100_000)),
    fn(seed_value) {
      let input =
        shrunk_input(fn() {
          metamon.forall_with(
            seeded(seed_value),
            digits(range.constant(5, 20)),
            fn(xs) {
              assert list.length(xs) < 5 || !list.contains(xs, 9)
            },
          )
        })
      // Five elements, one of them 9, the rest shrunk to 0.
      assert list.length(string.split(input, ", ")) == 5
        && string.contains(input, "9")
        && !string.contains(input, "1")
    },
  )
}

pub fn long_lists_generate_and_shrink_test() {
  let cfg = metamon.Config(..seeded(3), runs: 3)
  metamon.forall_with(
    cfg,
    generator.list_of(
      generator.int(range.constant(0, 1)),
      range.constant(20_000, 20_000),
    )
      |> generator.no_edges,
    fn(xs) {
      assert list.length(xs) == 20_000
    },
  )
  let input =
    shrunk_input(fn() {
      metamon.forall_with(
        cfg,
        generator.list_of(
          generator.int(range.constant(0, 1)),
          range.linear(0, 5000),
        )
          |> generator.no_edges
          |> generator.resize(99),
        fn(xs) {
          assert !list.contains(xs, 1)
        },
      )
    })
  assert input == "[1]"
}

pub fn non_empty_list_of_works_at_small_sizes_test() {
  metamon.forall(
    generator.non_empty_list_of(
      generator.int(range.constant(0, 9)),
      range.linear(0, 10),
    ),
    fn(xs) {
      assert xs != [] && list.length(xs) <= 10
    },
  )
}

pub fn non_empty_list_of_shrinks_to_one_element_test() {
  let input =
    shrunk_input(fn() {
      metamon.forall_with(
        seeded(8),
        generator.non_empty_list_of(
          generator.int(range.constant(0, 9)),
          range.linear(0, 10),
        )
          |> generator.no_edges,
        fn(xs) {
          assert list.length(xs) > 3
        },
      )
    })
  assert input == "[0]"
}

pub fn non_empty_list_of_rejects_a_range_without_non_empty_lengths_test() {
  let #(panicked, message) =
    test_helpers.capture_panic(fn() {
      let _ =
        generator.non_empty_list_of(generator.byte(), range.constant(0, 0))
      Nil
    })
  assert panicked
  assert string.contains(message, "metamon.non_empty_list_of")
}
