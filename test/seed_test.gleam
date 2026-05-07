import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should
import metamon/generator/seed.{type Seed}
import test_helpers

const default_state: Int = 0xDEADBEEF

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

pub fn seed_zero_is_rerouted_to_default_state_test() {
  // The xorshift family has 0 as a fixed point, so seed(0) is silently
  // replaced with 0xDEADBEEF.
  should.equal(seed.state(seed.seed(0)), default_state)
}

pub fn seed_negative_one_is_non_zero_test() {
  should.not_equal(seed.state(seed.seed(-1)), 0)
}

pub fn seed_overflow_collapses_to_default_state_test() {
  // 0x100000000 (= 2^32) masks to 0, which the rerouting then maps to
  // the default. seed(0) and seed(2^32) thus exercise the same stream.
  should.equal(seed.state(seed.seed(0x100000000)), default_state)
  should.equal(seed.state(seed.seed(0x100000000)), seed.state(seed.seed(0)))
}

pub fn original_input_records_user_value_test() {
  should.equal(seed.original_input(seed.seed(0)), Some(0))
  should.equal(seed.original_input(seed.seed(42)), Some(42))
  should.equal(seed.original_input(seed.seed(0x100000000)), Some(0x100000000))
}

pub fn original_input_is_none_for_advanced_seeds_test() {
  // Advancement (next_int / split) does not preserve the original
  // user input — only the seed handed to seed/1 has it.
  let s = seed.seed(42)
  let #(_, s2) = seed.next_int(s)
  should.equal(seed.original_input(s2), None)
  let #(left, right) = seed.split(s)
  should.equal(seed.original_input(left), None)
  should.equal(seed.original_input(right), None)
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
