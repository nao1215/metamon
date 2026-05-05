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

const mask_32: Int = 0xFFFFFFFF

const split_xor: Int = 0xA5A5A5A5

const default_state: Int = 0xDEADBEEF

/// Internal state of the PRNG. Always non-negative and ≤ `0xFFFFFFFF`.
/// The xorshift family has `0` as a fixed point, so a masked-to-zero
/// input is silently replaced with a non-zero default.
pub opaque type Seed {
  Seed(state: Int)
}

/// Construct a seed from an integer. Negative or out-of-range values
/// are normalised by masking to the 32-bit positive window so the
/// stream stays target-portable.
pub fn seed(value: Int) -> Seed {
  Seed(state: normalise(value))
}

/// Construct a seed from the system clock. Useful for ad-hoc local
/// runs; CI should pin a value via `metamon.with_seed(metamon.seed(_))`.
pub fn random_seed() -> Seed {
  Seed(state: normalise(now_microseconds()))
}

/// The raw integer state. Used by the regression-file format to
/// serialise a seed into a reproduction key.
pub fn state(s: Seed) -> Int {
  s.state
}

/// Advance the seed once and return the next non-negative integer
/// alongside the advanced seed.
pub fn next_int(s: Seed) -> #(Int, Seed) {
  let next_state = step(s.state)
  #(next_state, Seed(state: next_state))
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
  let #(a, _) = next_int(s)
  let xored = int.bitwise_and(int.bitwise_exclusive_or(a, split_xor), mask_32)
  let #(b, _) = next_int(Seed(state: xored))
  #(Seed(state: a), Seed(state: b))
}

fn step(state: Int) -> Int {
  // Marsaglia xorshift32. Each shift result is masked to 32 bits to
  // erase JS's signed-shift sign extension and BEAM's unbounded
  // arithmetic; the two targets thus produce the same value.
  let a =
    int.bitwise_exclusive_or(
      state,
      int.bitwise_and(int.bitwise_shift_left(state, 13), mask_32),
    )
  let b = int.bitwise_exclusive_or(a, int.bitwise_shift_right(a, 17))
  let c =
    int.bitwise_exclusive_or(
      b,
      int.bitwise_and(int.bitwise_shift_left(b, 5), mask_32),
    )
  int.bitwise_and(c, mask_32)
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
