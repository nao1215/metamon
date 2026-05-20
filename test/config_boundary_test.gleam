//// Centralised boundary tests for the validation interfaces of the
//// `metamon/config` builders and the `metamon/generator/range`
//// constructors. (#83)
////
//// `with_*` config builders return `Result(Config, ConfigError)`, so
//// boundary cases (zero, negative, very large) are pinned by inspecting
//// the returned `Result`. `range.constant` / `linear` / `exponential` /
//// `linear_from` panic on inverted bounds — those cases are pinned via
//// the same `metamon_ffi:capture_panic` helper that `range_test.gleam`
//// already uses for `linear_from`.

import gleam/option.{None}
import gleam/string
import gleeunit/should
import metamon/config
import metamon/generator/range

// ---------- shared panic-capture helper ----------

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

fn assert_panic_contains(outcome: PanicOutcome, fragment: String) -> Nil {
  case outcome {
    PanickedWith(message) -> should.be_true(string.contains(message, fragment))
    DidNotPanic -> should.fail()
  }
}

// ---------- with_runs ----------

pub fn with_runs_negative_is_rejected_test() {
  let c = config.default_config()
  case config.with_runs(c, -1) {
    Error(config.NonPositive("runs", -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_runs_zero_is_rejected_test() {
  let c = config.default_config()
  case config.with_runs(c, 0) {
    Error(config.NonPositive("runs", 0)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_runs_one_is_smallest_valid_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_runs(c, 1)
  should.equal(config.runs(c2), 1)
}

pub fn with_runs_very_large_is_accepted_test() {
  // Pin: the validator rejects only n <= 0; arbitrarily large n is
  // accepted and stored verbatim. Runtime overflow is not the
  // builder's responsibility.
  let c = config.default_config()
  let assert Ok(c2) = config.with_runs(c, 1_000_000_000)
  should.equal(config.runs(c2), 1_000_000_000)
}

// ---------- with_max_size ----------

pub fn with_max_size_negative_is_rejected_test() {
  let c = config.default_config()
  case config.with_max_size(c, -1) {
    Error(config.NonPositive("max_size", -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_max_size_zero_is_rejected_test() {
  let c = config.default_config()
  case config.with_max_size(c, 0) {
    Error(config.NonPositive("max_size", 0)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_max_size_one_is_smallest_valid_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_max_size(c, 1)
  should.equal(config.max_size(c2), 1)
}

pub fn with_max_size_very_large_is_accepted_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_max_size(c, 1_000_000_000)
  should.equal(config.max_size(c2), 1_000_000_000)
}

// ---------- with_shrink_limit ----------

pub fn with_shrink_limit_negative_is_rejected_test() {
  let c = config.default_config()
  case config.with_shrink_limit(c, -1) {
    Error(config.NonPositive("shrink_limit", -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_shrink_limit_zero_is_rejected_test() {
  // Pin: 0 is rejected (NonPositive). The issue #83 raises the
  // alternative "0 = no shrinking" semantics, but the implementation
  // chose the stricter Result contract — disabling shrinking is not
  // a documented use case, so callers should pass a positive bound.
  let c = config.default_config()
  case config.with_shrink_limit(c, 0) {
    Error(config.NonPositive("shrink_limit", 0)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_shrink_limit_one_is_smallest_valid_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_shrink_limit(c, 1)
  should.equal(config.shrink_limit(c2), 1)
}

pub fn with_shrink_limit_very_large_is_accepted_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_shrink_limit(c, 1_000_000_000)
  should.equal(config.shrink_limit(c2), 1_000_000_000)
}

// ---------- with_max_edges ----------

pub fn with_max_edges_negative_is_rejected_test() {
  let c = config.default_config()
  case config.with_max_edges(c, -1) {
    Error(config.NonPositive("max_edges", -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_max_edges_zero_is_rejected_test() {
  // Pin: 0 is rejected. The issue raises "0 = no edges considered",
  // but the implementation forces a positive cap so the runner always
  // has at least one edge slot.
  let c = config.default_config()
  case config.with_max_edges(c, 0) {
    Error(config.NonPositive("max_edges", 0)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_max_edges_one_is_smallest_valid_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_max_edges(c, 1)
  should.equal(config.max_edges(c2), 1)
}

pub fn with_max_edges_very_large_is_accepted_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_max_edges(c, 1_000_000_000)
  should.equal(config.max_edges(c2), 1_000_000_000)
}

// ---------- with_regression_file ----------

pub fn with_regression_file_empty_is_rejected_test() {
  let c = config.default_config()
  case config.with_regression_file(c, "") {
    Error(config.InvalidPath("", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_regression_file_default_is_none_test() {
  let c = config.default_config()
  should.equal(config.regression_file(c), None)
}

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
