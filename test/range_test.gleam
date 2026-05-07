import gleam/list
import gleam/string
import gleeunit/should
import metamon/generator/range
import test_helpers

pub fn singleton_is_constant_test() {
  let r = range.singleton(7)
  should.equal(range.origin(r), 7)
  should.equal(range.bounds(r, 0, 99), #(7, 7))
  should.equal(range.bounds(r, 99, 99), #(7, 7))
}

pub fn constant_ignores_size_test() {
  let r = range.constant(0, 100)
  should.equal(range.bounds(r, 0, 99), #(0, 100))
  should.equal(range.bounds(r, 50, 99), #(0, 100))
  should.equal(range.bounds(r, 99, 99), #(0, 100))
}

pub fn constant_picks_zero_origin_when_in_range_test() {
  should.equal(range.origin(range.constant(-10, 10)), 0)
  should.equal(range.origin(range.constant(5, 100)), 5)
}

pub fn linear_size_zero_collapses_to_origin_test() {
  let r = range.linear(0, 100)
  should.equal(range.bounds(r, 0, 99), #(0, 0))
}

pub fn linear_size_max_reaches_full_range_test() {
  let r = range.linear(0, 100)
  should.equal(range.bounds(r, 99, 99), #(0, 100))
}

pub fn linear_from_uses_explicit_origin_test() {
  let r = range.linear_from(2000, 1900, 2100)
  should.equal(range.origin(r), 2000)
  should.equal(range.bounds(r, 0, 99), #(2000, 2000))
  should.equal(range.bounds(r, 99, 99), #(1900, 2100))
}

pub fn linear_from_accepts_origin_at_boundaries_test() {
  // Origin equal to lo and to hi are inclusive endpoints.
  let r_lo = range.linear_from(0, 0, 10)
  should.equal(range.origin(r_lo), 0)
  let r_hi = range.linear_from(10, 0, 10)
  should.equal(range.origin(r_hi), 10)
}

pub fn linear_from_panics_when_origin_below_lo_test() {
  let outcome =
    capture_panic(fn() {
      let _ = range.linear_from(-5, 0, 10)
      Nil
    })
  case outcome {
    PanickedWith(message) -> {
      should.be_true(string.contains(message, "origin must lie inside [lo, hi]"))
    }
    DidNotPanic -> should.fail()
  }
}

pub fn linear_from_panics_when_origin_above_hi_test() {
  let outcome =
    capture_panic(fn() {
      let _ = range.linear_from(100, 0, 10)
      Nil
    })
  case outcome {
    PanickedWith(message) -> {
      should.be_true(string.contains(message, "origin must lie inside [lo, hi]"))
    }
    DidNotPanic -> should.fail()
  }
}

pub type PanicOutcome {
  PanickedWith(message: String)
  DidNotPanic
}

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic_raw(thunk: fn() -> Nil) -> #(Bool, String)

fn capture_panic(thunk: fn() -> Nil) -> PanicOutcome {
  let #(panicked, message) = capture_panic_raw(thunk)
  case panicked {
    True -> PanickedWith(message: message)
    False -> DidNotPanic
  }
}

pub fn exponential_grows_quadratically_test() {
  let r = range.exponential(0, 100)
  let #(_, hi_low) = range.bounds(r, 10, 99)
  let #(_, hi_high) = range.bounds(r, 90, 99)
  // 90^2 / 99^2 ≈ 0.826, 10^2 / 99^2 ≈ 0.010 — large gap expected
  should.be_true(hi_high - hi_low > 50)
}

pub fn bounds_clamp_size_into_valid_window_test() {
  let r = range.linear(0, 50)
  // size below zero clamps to 0, size above max clamps to max
  should.equal(range.bounds(r, -10, 99), range.bounds(r, 0, 99))
  should.equal(range.bounds(r, 1000, 99), range.bounds(r, 99, 99))
}

pub fn random_check_values_within_bounds_test() {
  let r = range.linear(0, 100)
  test_helpers.integers_from(0, 100)
  |> list.each(fn(size) {
    let #(lo, hi) = range.bounds(r, size, 99)
    should.be_true(lo <= hi)
    should.be_true(lo >= 0 && hi <= 100)
  })
}
