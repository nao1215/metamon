//// The interval behind `generator.range` and `generator.linear_range`:
//// bounds at each size, the shrink origin, swapped bounds and extreme
//// bounds.

import gleam/list
import gleeunit/should
import metamon/generator
import metamon/internal/interval.{Constant, Linear}
import metamon/internal/seed
import metamon/internal/tree.{Done, More}
import test_helpers

fn constant(from: Int, to: Int) -> interval.Interval {
  interval.new(from, to, Constant)
}

fn linear(from: Int, to: Int) -> interval.Interval {
  interval.new(from, to, Linear)
}

pub fn equal_bounds_are_constant_test() {
  let r = constant(7, 7)
  should.equal(r.origin, 7)
  should.equal(interval.bounds(r, 0, 99), #(7, 7))
  should.equal(interval.bounds(r, 99, 99), #(7, 7))
  should.equal(interval.bounds(linear(5, 5), 50, 99), #(5, 5))
}

pub fn constant_ignores_size_test() {
  let r = constant(0, 100)
  should.equal(interval.bounds(r, 0, 99), #(0, 100))
  should.equal(interval.bounds(r, 50, 99), #(0, 100))
  should.equal(interval.bounds(r, 99, 99), #(0, 100))
}

pub fn origin_is_zero_when_in_range_test() {
  should.equal(constant(-10, 10).origin, 0)
  should.equal(constant(5, 100).origin, 5)
  should.equal(linear(-5, 5).origin, 0)
  should.equal(linear(3, 9).origin, 3)
  should.equal(linear(-9, -3).origin, -9)
}

pub fn linear_size_zero_collapses_to_origin_test() {
  should.equal(interval.bounds(linear(0, 100), 0, 99), #(0, 0))
}

pub fn linear_size_max_reaches_full_range_test() {
  should.equal(interval.bounds(linear(0, 100), 99, 99), #(0, 100))
}

pub fn bounds_clamp_size_into_valid_window_test() {
  let r = linear(0, 50)
  should.equal(interval.bounds(r, -10, 99), interval.bounds(r, 0, 99))
  should.equal(interval.bounds(r, 1000, 99), interval.bounds(r, 99, 99))
}

pub fn linear_bounds_stay_inside_the_range_test() {
  let r = linear(0, 100)
  test_helpers.integers_from(0, 100)
  |> list.each(fn(size) {
    let #(lo, hi) = interval.bounds(r, size, 99)
    should.be_true(lo <= hi)
    should.be_true(lo >= 0 && hi <= 100)
  })
}

pub fn inverted_bounds_are_swapped_test() {
  should.equal(interval.bounds(constant(10, 0), 0, 99), #(0, 10))
  should.equal(interval.bounds(linear(10, 0), 99, 99), #(0, 10))
}

pub fn extreme_bounds_do_not_overflow_test() {
  let r = constant(-1_000_000_000, 1_000_000_000)
  should.equal(interval.bounds(r, 0, 99), #(-1_000_000_000, 1_000_000_000))
  should.equal(interval.bounds(r, 99, 99), #(-1_000_000_000, 1_000_000_000))
  let l = linear(-1_000_000_000, 1_000_000_000)
  should.equal(l.origin, 0)
  should.equal(interval.bounds(l, 0, 99), #(0, 0))
}

pub fn int_values_shrink_toward_the_origin_test() {
  // The first shrink of an integer is the origin of its range.
  let g = generator.int(generator.range(from: 5, to: 100))
  test_helpers.integers_from(0, 20)
  |> list.each(fn(i) {
    let t = generator.generate(g, seed.seed(i), 99, 99)
    case t.value == 5, t.shrinks.step() {
      True, _ -> Nil
      False, More(first, _) -> should.equal(first.value, 5)
      False, Done -> should.fail()
    }
  })
}
