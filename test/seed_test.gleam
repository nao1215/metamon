import gleam/list
import gleam/set
import gleeunit/should
import metamon/generator/seed.{type Seed}
import test_helpers

pub fn seed_is_deterministic_test() {
  let s = seed.seed(42)
  let #(a, _) = seed.next_int(s)
  let #(b, _) = seed.next_int(s)
  should.equal(a, b)
}

pub fn next_int_advances_state_test() {
  let s = seed.seed(42)
  let #(_, s2) = seed.next_int(s)
  should.not_equal(seed.state(s), seed.state(s2))
}

pub fn next_int_in_respects_bounds_test() {
  let bounds_ok = fn(s: Seed, lo: Int, hi: Int) {
    let #(value, _) = seed.next_int_in(s, lo, hi)
    value >= lo && value <= hi
  }
  test_helpers.integers_from(0, 50)
  |> list.each(fn(i) {
    should.be_true(bounds_ok(seed.seed(i), 0, 100))
    should.be_true(bounds_ok(seed.seed(i), -10, 10))
    should.be_true(bounds_ok(seed.seed(i), 1000, 2000))
  })
}

pub fn next_int_in_singleton_test() {
  let #(value, _) = seed.next_int_in(seed.seed(7), 99, 99)
  should.equal(value, 99)
}

pub fn next_int_in_swaps_inverted_bounds_test() {
  let #(value, _) = seed.next_int_in(seed.seed(1), 50, 10)
  should.be_true(value >= 10 && value <= 50)
}

pub fn split_yields_independent_streams_test() {
  let #(left, right) = seed.split(seed.seed(123))
  should.not_equal(seed.state(left), seed.state(right))
  let #(a, _) = seed.next_int(left)
  let #(b, _) = seed.next_int(right)
  should.not_equal(a, b)
}

pub fn long_run_distribution_is_spread_test() {
  // Pull 200 numbers in [0, 99] and assert at least 50 distinct values.
  // A broken PRNG (constant or short period) will fail this trivially.
  let values =
    test_helpers.integers_from(0, 200)
    |> list.fold(#(seed.seed(2026), []), fn(acc, _i) {
      let #(s, acc_values) = acc
      let #(value, s2) = seed.next_int_in(s, 0, 99)
      #(s2, [value, ..acc_values])
    })
    |> fn(pair) { pair.1 }
  let distinct = values |> set.from_list() |> set.size()
  should.be_true(distinct >= 50)
}
