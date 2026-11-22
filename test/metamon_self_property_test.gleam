//// metamon-driven property tests for parts of metamon's own surface
//// that the existing per-feature test files exercise with point
//// fixtures rather than property runs. These complement
//// `test/relation_test.gleam` and `test/generator_test.gleam` by
//// re-checking the same laws against metamon-generated inputs.

import gleam/int
import gleam/list
import metamon
import metamon/generator

pub fn relation_equal_is_reflexive_test() {
  metamon.forall(generator.int(generator.range(-100, 100)), fn(value) {
    let equal = metamon.equal()
    assert equal.holds(value, value)
  })
}

pub fn relation_equal_is_symmetric_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(generator.range(-50, 50)),
      generator.int(generator.range(-50, 50)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let equal = metamon.equal()
      assert equal.holds(left, right) == equal.holds(right, left)
    },
  )
}

pub fn relation_permutation_holds_for_reverse_test() {
  metamon.forall(
    generator.list_of(
      generator.int(generator.range(-50, 50)),
      generator.range(0, 6),
    ),
    fn(items) {
      let perm = metamon.permutation_of()
      assert perm.holds(items, list.reverse(items))
    },
  )
}

pub fn relation_permutation_self_test() {
  metamon.forall(
    generator.list_of(
      generator.int(generator.range(-50, 50)),
      generator.range(0, 6),
    ),
    fn(items) {
      let perm = metamon.permutation_of()
      assert perm.holds(items, items)
    },
  )
}

pub fn relation_approximately_zero_epsilon_is_equal_test() {
  metamon.forall(generator.int(generator.range(-1000, 1000)), fn(value) {
    let approx = metamon.approximately(0.0)
    let as_float = int.to_float(value)
    assert approx.holds(as_float, as_float)
  })
}

// ---------- generator bounds ----------

pub fn generator_int_constant_range_respects_bounds_test() {
  metamon.forall(generator.int(generator.range(-25, 25)), fn(value) {
    assert value >= -25 && value <= 25
  })
}

pub fn generator_linear_range_from_zero_is_non_negative_test() {
  metamon.forall(generator.int(generator.linear_range(0, 1_000_000)), fn(value) {
    assert value >= 0
  })
}

pub fn generator_linear_range_from_one_is_positive_test() {
  metamon.forall(generator.int(generator.linear_range(1, 1_000_000)), fn(value) {
    assert value >= 1
  })
}

pub fn generator_linear_range_to_minus_one_is_negative_test() {
  metamon.forall(
    generator.int(generator.linear_range(-1_000_000, -1)),
    fn(value) {
      assert value <= -1
    },
  )
}

pub fn generator_int_is_in_byte_range_test() {
  metamon.forall(generator.int(generator.range(0, 255)), fn(value) {
    assert value >= 0 && value <= 255
  })
}

pub fn generator_list_length_respects_size_range_test() {
  metamon.forall(
    generator.list_of(
      generator.int(generator.range(0, 9)),
      generator.range(0, 5),
    ),
    fn(items) {
      let length = list.length(items)
      assert length >= 0 && length <= 5
    },
  )
}

pub fn generator_list_keeps_the_lower_length_bound_test() {
  metamon.forall(
    generator.list_of(
      generator.int(generator.range(0, 9)),
      generator.range(1, 5),
    ),
    fn(items) {
      assert list.length(items) >= 1
    },
  )
}
