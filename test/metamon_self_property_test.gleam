//// metamon-driven property tests for parts of metamon's own surface
//// that the existing per-feature test files exercise with point
//// fixtures rather than property runs. These complement
//// `test/relation_test.gleam` and `test/generator_test.gleam` by
//// re-checking the same laws against metamon-generated inputs.

import gleam/int
import gleam/list
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation

pub fn relation_equal_is_reflexive_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let equal = relation.equal()
    assert equal.holds(value, value)
  })
}

pub fn relation_equal_is_symmetric_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let equal = relation.equal()
      assert equal.holds(left, right) == equal.holds(right, left)
    },
  )
}

pub fn relation_permutation_holds_for_reverse_test() {
  metamon.forall(
    generator.list_of(
      generator.int(range.constant(-50, 50)),
      range.constant(0, 6),
    ),
    fn(items) {
      let perm = relation.permutation_of()
      assert perm.holds(items, list.reverse(items))
    },
  )
}

pub fn relation_permutation_self_test() {
  metamon.forall(
    generator.list_of(
      generator.int(range.constant(-50, 50)),
      range.constant(0, 6),
    ),
    fn(items) {
      let perm = relation.permutation_of()
      assert perm.holds(items, items)
    },
  )
}

pub fn relation_approximately_zero_epsilon_is_equal_test() {
  metamon.forall(generator.int(range.constant(-1000, 1000)), fn(value) {
    let approx = relation.approximately(0.0)
    let as_float = int.to_float(value)
    assert approx.holds(as_float, as_float)
  })
}

// ---------- generator bounds ----------

pub fn generator_int_constant_range_respects_bounds_test() {
  metamon.forall(generator.int(range.constant(-25, 25)), fn(value) {
    assert value >= -25 && value <= 25
  })
}

pub fn generator_non_negative_int_is_non_negative_test() {
  metamon.forall(generator.non_negative_int(), fn(value) {
    assert value >= 0
  })
}

pub fn generator_positive_int_is_positive_test() {
  metamon.forall(generator.positive_int(), fn(value) {
    assert value >= 1
  })
}

pub fn generator_negative_int_is_negative_test() {
  metamon.forall(generator.negative_int(), fn(value) {
    assert value <= -1
  })
}

pub fn generator_byte_is_in_byte_range_test() {
  metamon.forall(generator.byte(), fn(value) {
    assert value >= 0 && value <= 255
  })
}

pub fn generator_list_length_respects_size_range_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    fn(items) {
      let length = list.length(items)
      assert length >= 0 && length <= 5
    },
  )
}

pub fn generator_non_empty_list_has_at_least_one_element_test() {
  metamon.forall(
    generator.non_empty_list_of(
      generator.int(range.constant(0, 9)),
      range.constant(1, 5),
    ),
    fn(items) {
      assert list.length(items) >= 1
    },
  )
}
