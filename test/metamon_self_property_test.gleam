//// metamon-driven property tests for parts of metamon's own surface
//// that the existing per-feature test files exercise with point
//// fixtures rather than property runs. These complement
//// `test/transform_test.gleam`, `test/relation_test.gleam`, and
//// `test/generator_test.gleam` by re-checking the same laws against
//// metamon-generated inputs.

import gleam/int
import gleam/list
import gleam/order
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform

// ---------- transform.then composition ----------

pub fn transform_then_applies_left_then_right_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let plus_one = transform.new("plus_one", fn(input) { input + 1 })
    let times_two = transform.new("times_two", fn(input) { input * 2 })
    let composed = transform.then(plus_one, times_two)
    composed.apply(value) == { value + 1 } * 2
  })
}

pub fn transform_then_is_associative_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let plus_one = transform.new("plus_one", fn(input) { input + 1 })
    let times_two = transform.new("times_two", fn(input) { input * 2 })
    let minus_three = transform.new("minus_three", fn(input) { input - 3 })
    let left = transform.then(transform.then(plus_one, times_two), minus_three)
    let right = transform.then(plus_one, transform.then(times_two, minus_three))
    left.apply(value) == right.apply(value)
  })
}

pub fn transform_identity_is_two_sided_neutral_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let plus_one = transform.new("plus_one", fn(input) { input + 1 })
    let id = transform.identity()
    transform.then(id, plus_one).apply(value) == plus_one.apply(value)
    && transform.then(plus_one, id).apply(value) == plus_one.apply(value)
  })
}

pub fn transform_repeat_zero_is_identity_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let plus_one = transform.new("plus_one", fn(input) { input + 1 })
    transform.repeat(plus_one, 0).apply(value) == value
  })
}

pub fn transform_repeat_negative_is_identity_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let plus_one = transform.new("plus_one", fn(input) { input + 1 })
    transform.repeat(plus_one, -5).apply(value) == value
  })
}

pub fn transform_repeat_n_equals_n_compositions_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-100, 100)),
      generator.int(range.constant(0, 5)),
    ),
    fn(pair) {
      let #(value, n) = pair
      let plus_one = transform.new("plus_one", fn(input) { input + 1 })
      transform.repeat(plus_one, n).apply(value) == value + n
    },
  )
}

pub fn transform_constant_ignores_input_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-100, 100)),
      generator.int(range.constant(-100, 100)),
    ),
    fn(pair) {
      let #(input, output) = pair
      let const_t = transform.constant("const", output)
      const_t.apply(input) == output
    },
  )
}

// ---------- relation combinators ----------

pub fn relation_and_is_logical_intersection_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let positive_left =
        relation.new("positive_left", fn(left_value, _right_value) {
          left_value > 0
        })
      let nonzero_right =
        relation.new("nonzero_right", fn(_left_value, right_value) {
          right_value != 0
        })
      let combined = relation.and(positive_left, nonzero_right)
      combined.holds(left, right) == { left > 0 && right != 0 }
    },
  )
}

pub fn relation_or_is_logical_union_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-20, 20)),
      generator.int(range.constant(-20, 20)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let left_positive =
        relation.new("left_positive", fn(left_value, _right_value) {
          left_value > 0
        })
      let right_positive =
        relation.new("right_positive", fn(_left_value, right_value) {
          right_value > 0
        })
      let combined = relation.or(left_positive, right_positive)
      combined.holds(left, right) == { left > 0 || right > 0 }
    },
  )
}

pub fn relation_invert_negates_holds_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-20, 20)),
      generator.int(range.constant(-20, 20)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let equal = relation.equal()
      let inverted = relation.invert(equal)
      inverted.holds(left, right) == !equal.holds(left, right)
    },
  )
}

pub fn relation_invert_is_involutive_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-20, 20)),
      generator.int(range.constant(-20, 20)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let equal = relation.equal()
      let twice = relation.invert(relation.invert(equal))
      twice.holds(left, right) == equal.holds(left, right)
    },
  )
}

pub fn relation_equal_is_reflexive_test() {
  metamon.forall(generator.int(range.constant(-100, 100)), fn(value) {
    let equal = relation.equal()
    equal.holds(value, value)
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
      equal.holds(left, right) == equal.holds(right, left)
    },
  )
}

pub fn relation_not_equal_is_negation_of_equal_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let equal = relation.equal()
      let not_equal = relation.not_equal()
      not_equal.holds(left, right) == !equal.holds(left, right)
    },
  )
}

pub fn relation_monotone_matches_compare_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    fn(pair) {
      let #(left, right) = pair
      let mono = relation.monotone(int.compare)
      let expected = case int.compare(left, right) {
        order.Lt | order.Eq -> True
        order.Gt -> False
      }
      mono.holds(left, right) == expected
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
      perm.holds(items, list.reverse(items))
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
      perm.holds(items, items)
    },
  )
}

pub fn relation_subset_self_test() {
  metamon.forall(
    generator.list_of(
      generator.int(range.constant(-50, 50)),
      range.constant(0, 6),
    ),
    fn(items) {
      let subset = relation.subset_of()
      subset.holds(items, items)
    },
  )
}

pub fn relation_set_subset_holds_for_appended_extra_test() {
  metamon.forall(
    generator.tuple2(
      generator.list_of(
        generator.int(range.constant(0, 9)),
        range.constant(0, 4),
      ),
      generator.int(range.constant(0, 9)),
    ),
    fn(pair) {
      let #(items, extra) = pair
      let set_subset = relation.set_subset_of()
      // Every element of `items` is, by construction, present in
      // `[extra, ..items]` regardless of `extra`.
      set_subset.holds(items, [extra, ..items])
    },
  )
}

pub fn relation_approximately_zero_epsilon_is_equal_test() {
  metamon.forall(generator.int(range.constant(-1000, 1000)), fn(value) {
    let approx = relation.approximately(0.0)
    let as_float = int.to_float(value)
    approx.holds(as_float, as_float)
  })
}

// ---------- generator bounds ----------

pub fn generator_int_constant_range_respects_bounds_test() {
  metamon.forall(generator.int(range.constant(-25, 25)), fn(value) {
    value >= -25 && value <= 25
  })
}

pub fn generator_non_negative_int_is_non_negative_test() {
  metamon.forall(generator.non_negative_int(), fn(value) { value >= 0 })
}

pub fn generator_positive_int_is_positive_test() {
  metamon.forall(generator.positive_int(), fn(value) { value >= 1 })
}

pub fn generator_negative_int_is_negative_test() {
  metamon.forall(generator.negative_int(), fn(value) { value <= -1 })
}

pub fn generator_byte_is_in_byte_range_test() {
  metamon.forall(generator.byte(), fn(value) { value >= 0 && value <= 255 })
}

pub fn generator_list_length_respects_size_range_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    fn(items) {
      let length = list.length(items)
      length >= 0 && length <= 5
    },
  )
}

pub fn generator_non_empty_list_has_at_least_one_element_test() {
  metamon.forall(
    generator.non_empty_list_of(
      generator.int(range.constant(0, 9)),
      range.constant(1, 5),
    ),
    fn(items) { list.length(items) >= 1 },
  )
}
