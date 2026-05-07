//// Deterministic pseudo-random seed.
////
//// The implementation is the 32-bit "Marsaglia xorshift" PRNG. It
//// uses only shifts and xors — no multiplication — so BEAM (bignum
//// integers) and JavaScript (53-bit safe doubles) produce
//// bit-identical streams. An LCG-style multiplier would overflow
//// JavaScript's double precision well before the 32-bit mask and
//// cause subtle distribution drift.
////
//// Statistical quality is not the goal here — determinism and
//// portability are. Property-based testing is well-served even by
//// modest PRNGs because the failure search is shrinker-driven, not
//// statistical.

import gleam/int
import gleam/option.{type Option, None, Some}

const mask_32: Int = 0xFFFFFFFF

const split_xor: Int = 0xA5A5A5A5

const default_state: Int = 0xDEADBEEF

/// Internal state of the PRNG. Always non-negative and ≤ `0xFFFFFFFF`.
/// The xorshift family has `0` as a fixed point, so a masked-to-zero
/// input is silently replaced with a non-zero default.
///
/// `original_input` records the integer the user originally passed to
/// `seed/1` (if any) so failure reports can annotate the canonical
/// state with the user-visible value when normalisation kicked in.
pub opaque type Seed {
  Seed(state: Int, original_input: Option(Int))
}

/// Construct a seed from an integer.
///
/// The integer is masked to a 32-bit non-negative window so the
/// stream stays target-portable. A masked-to-zero value is silently
/// replaced with `0xDEADBEEF` because the xorshift family has `0` as
/// a fixed point — emitting it would degenerate the stream.
///
/// Both normalisation steps mean `seed(0)`, `seed(0x100000000)` (= 2^32),
/// and any other `value` whose 32-bit-masked form is `0` collapse to
/// the same canonical state. Failure reports annotate the canonical
/// state with the original input when normalisation kicked in (see
/// `original_input/1`).
pub fn seed(value: Int) -> Seed {
  Seed(state: normalise(value), original_input: Some(value))
}

/// Construct a seed from the system clock. Useful for ad-hoc local
/// runs; CI should pin a value via `metamon.with_seed(metamon.seed(_))`.
pub fn random_seed() -> Seed {
  Seed(state: normalise(now_microseconds()), original_input: None)
}

/// The raw integer state. Used by the regression-file format to
/// serialise a seed into a reproduction key.
pub fn state(s: Seed) -> Int {
  s.state
}

/// The integer the user passed to `seed/1`, if any.
///
/// `None` for seeds derived from the system clock, from `next_int` /
/// `next_int_in` advancement, or from `split`. `Some(n)` for seeds
/// constructed via `seed(n)`. Failure reports compare this against
/// `state/1` to decide whether to annotate "originally seed(n)".
pub fn original_input(s: Seed) -> Option(Int) {
  s.original_input
}

/// Advance the seed once and return the next non-negative integer
/// alongside the advanced seed.
pub fn next_int(s: Seed) -> #(Int, Seed) {
  let next_state = step(s.state)
  #(next_state, Seed(state: next_state, original_input: None))
}

/// Return an integer uniformly in the closed interval `[lo, hi]`.
///
/// If `lo > hi` the bounds are swapped. If `lo == hi` the bound is
/// returned without consuming randomness (the seed is still advanced
/// for determinism).
pub fn next_int_in(s: Seed, lo: Int, hi: Int) -> #(Int, Seed) {
  let #(low, high) = case lo > hi {
    True -> #(hi, lo)
    False -> #(lo, hi)
  }
  case low == high {
    True -> {
      let #(_, s2) = next_int(s)
      #(low, s2)
    }
    False -> {
      let #(raw, s2) = next_int(s)
      let span = high - low + 1
      #(low + raw % span, s2)
    }
  }
}

/// Split a seed into two statistically independent seeds. The
/// implementation derives the second seed by xor-ing the first with a
/// constant before stepping, which on a 32-bit LCG produces a stream
/// that does not align with the original — sufficient for shrinking
/// independent generator components without correlation artefacts.
pub fn split(s: Seed) -> #(Seed, Seed) {
  let #(left_state, _) = next_int(s)
  let xored =
    int.bitwise_and(int.bitwise_exclusive_or(left_state, split_xor), mask_32)
  let #(right_state, _) = next_int(Seed(state: xored, original_input: None))
  #(
    Seed(state: left_state, original_input: None),
    Seed(state: right_state, original_input: None),
  )
}

fn step(state: Int) -> Int {
  // Marsaglia xorshift32. Each shift result is masked to 32 bits to
  // erase JS's signed-shift sign extension and BEAM's unbounded
  // arithmetic; the two targets thus produce the same value.
  let after_first_shift =
    int.bitwise_exclusive_or(
      state,
      int.bitwise_and(int.bitwise_shift_left(state, 13), mask_32),
    )
  let after_second_shift =
    int.bitwise_exclusive_or(
      after_first_shift,
      int.bitwise_shift_right(after_first_shift, 17),
    )
  let after_third_shift =
    int.bitwise_exclusive_or(
      after_second_shift,
      int.bitwise_and(int.bitwise_shift_left(after_second_shift, 5), mask_32),
    )
  int.bitwise_and(after_third_shift, mask_32)
}

fn normalise(value: Int) -> Int {
  let positive = case value < 0 {
    True -> 0 - value
    False -> value
  }
  let masked = int.bitwise_and(positive, mask_32)
  case masked {
    0 -> default_state
    n -> n
  }
}

@external(erlang, "metamon_ffi", "now_microseconds")
@external(javascript, "../../metamon_ffi.mjs", "now_microseconds")
fn now_microseconds() -> Int
