//// Boundary tests for the `metamon/generator/range` constructors:
//// singleton pairs, inverted bounds (swapped, not rejected) and
//// extreme bounds.

import gleeunit/should
import metamon/generator/range

// ---------- range.singleton ----------

pub fn range_singleton_origin_equals_value_test() {
  should.equal(range.origin(range.singleton(7)), 7)
}

pub fn range_singleton_min_int_test() {
  // Pin: arbitrarily small / negative values are accepted verbatim.
  let r = range.singleton(-1_000_000_000)
  should.equal(range.origin(r), -1_000_000_000)
  should.equal(range.bounds(r, 0, 99), #(-1_000_000_000, -1_000_000_000))
}

// ---------- range.constant ----------

pub fn range_constant_singleton_pair_is_constant_test() {
  // Pin: a (n, n) pair behaves as a singleton at every size.
  let r = range.constant(5, 5)
  should.equal(range.origin(r), 5)
  should.equal(range.bounds(r, 0, 99), #(5, 5))
  should.equal(range.bounds(r, 99, 99), #(5, 5))
}

pub fn range_constant_inverted_bounds_auto_swap_test() {
  // Pin: as of #89, inverted bounds are auto-swapped to match the
  // `generator.float` lenient convention rather than panicking. The
  // resulting bounds are normalised to `[hi, lo]`.
  let r = range.constant(10, 0)
  should.equal(range.bounds(r, 0, 99), #(0, 10))
}

pub fn range_constant_extreme_bounds_no_overflow_test() {
  // Pin: huge bounds compute without crash. `bounds` returns the
  // verbatim pair for `Const` regardless of size.
  let r = range.constant(-1_000_000_000, 1_000_000_000)
  should.equal(range.bounds(r, 0, 99), #(-1_000_000_000, 1_000_000_000))
  should.equal(range.bounds(r, 99, 99), #(-1_000_000_000, 1_000_000_000))
}

// ---------- range.linear ----------

pub fn range_linear_inverted_bounds_auto_swap_test() {
  let r = range.linear(10, 0)
  should.equal(range.bounds(r, 99, 99), #(0, 10))
}

pub fn range_linear_extreme_bounds_no_overflow_at_size_zero_test() {
  // Pin: at size = 0 the bounds collapse to the chosen origin (0
  // when 0 is inside the interval) without arithmetic crash.
  let r = range.linear(-1_000_000_000, 1_000_000_000)
  should.equal(range.origin(r), 0)
  should.equal(range.bounds(r, 0, 99), #(0, 0))
}

// ---------- range.linear_from ----------

pub fn range_linear_from_inverted_bounds_auto_swap_test() {
  // #89 auto-swaps inverted `lo > hi` pairs. With swapping, an
  // origin of 5 lies inside the normalised [0, 10] bounds and the
  // range is constructed successfully.
  let r = range.linear_from(5, 10, 0)
  should.equal(range.origin(r), 5)
  should.equal(range.bounds(r, 99, 99), #(0, 10))
}

// ---------- range.exponential ----------

pub fn range_exponential_inverted_bounds_auto_swap_test() {
  let r = range.exponential(10, 0)
  should.equal(range.bounds(r, 99, 99), #(0, 10))
}

pub fn range_exponential_singleton_pair_is_constant_test() {
  // Pin: a (n, n) pair behaves as a singleton at every size — there
  // is nothing to scale exponentially when bounds collide.
  let r = range.exponential(5, 5)
  should.equal(range.bounds(r, 0, 99), #(5, 5))
  should.equal(range.bounds(r, 50, 99), #(5, 5))
  should.equal(range.bounds(r, 99, 99), #(5, 5))
}
