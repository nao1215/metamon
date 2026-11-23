//// Generated values cover the whole range they are drawn from.

import gleam/float
import gleam/int
import gleam/list
import metamon/generator
import metamon/internal/seed

pub fn a_range_wider_than_32_bits_reaches_its_upper_part_test() {
  let values =
    generator.int(generator.range(from: 0, to: 1_000_000_000_000))
    |> generator.sample(count: 1000, seed: 1)
  // About half of the values lie above the midpoint.
  let upper = list.count(values, fn(n) { n > 500_000_000_000 })
  assert upper > 400 && upper < 600
}

pub fn the_safe_integer_range_produces_both_signs_test() {
  let values =
    generator.int(generator.range(
      from: -9_007_199_254_740_991,
      to: 9_007_199_254_740_991,
    ))
    |> generator.sample(count: 1000, seed: 1)
  let positive = list.count(values, fn(n) { n > 0 })
  assert positive > 400 && positive < 600
  assert list.all(values, fn(n) {
    n >= -9_007_199_254_740_991 && n <= 9_007_199_254_740_991
  })
}

pub fn a_range_near_32_bits_is_not_biased_toward_its_lower_part_test() {
  // 3 * 2^30 values: a 32-bit draw reduced modulo the span hits the
  // lower third twice as often as the rest.
  let values =
    generator.int(generator.range(from: 0, to: 3_221_225_471))
    |> generator.sample(count: 3000, seed: 7)
  let lower_third = list.count(values, fn(n) { n < 1_073_741_824 })
  assert lower_third > 850 && lower_third < 1150
}

pub fn wide_draws_are_the_same_on_both_targets_test() {
  // A fixed seed gives the same value on Erlang and JavaScript.
  let #(value, _) = seed.next_int_in(seed.seed(42), 0, 1_000_000_000_000)
  assert value == 215_634_261_525
}

pub fn a_float_range_as_wide_as_the_doubles_does_not_overflow_test() {
  let values =
    generator.float(from: -1.7e308, to: 1.7e308)
    |> generator.sample(count: 200, seed: 1)
  assert list.all(values, fn(x) { x >=. -1.7e308 && x <=. 1.7e308 })
  assert list.any(values, fn(x) { x >. 0.0 })
  assert list.any(values, fn(x) { x <. 0.0 })
}

pub fn floats_are_not_limited_to_a_million_steps_test() {
  // 1_000_000 evenly spaced fractions can only give multiples of 1e-6.
  let values =
    generator.float(from: 0.0, to: 1.0)
    |> generator.sample(count: 200, seed: 3)
  let off_grid =
    list.count(values, fn(x) {
      let scaled = x *. 1_000_000.0
      float.absolute_value(scaled -. int.to_float(float.round(scaled)))
      >. 1.0e-3
    })
  assert off_grid > 150
}

pub fn the_safe_integer_range_produces_even_and_odd_values_test() {
  // On JavaScript, accumulating 32-bit draws past 2^53 rounded every
  // value onto a coarse grid of odd numbers.
  let values =
    generator.int(generator.range(
      from: -9_007_199_254_740_991,
      to: 9_007_199_254_740_991,
    ))
    |> generator.sample(count: 1000, seed: 2)
  let even = list.count(values, int.is_even)
  assert even > 400 && even < 600
  assert list.length(list.unique(values)) > 990
}
