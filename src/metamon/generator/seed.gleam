//// Deterministic pseudo-random seed based on splitmix64.
////
//// Pure-Gleam, target-agnostic (BEAM and JS produce identical streams).
//// Provides `split`, `next_int`, and `next_int_in` so generators can derive
//// independent sub-streams without depending on Erlang's `rand` module or
//// any external library.

import gleam/int

/// Internal state of the splitmix64 PRNG.
///
/// 64-bit unsigned arithmetic is emulated with a 64-bit mask so the BEAM
/// (arbitrary-precision integers) and JavaScript (BigInt-promoted) targets
/// produce the same numeric stream.
pub opaque type Seed {
  Seed(state: Int)
}

const mask_64: Int = 0xFFFFFFFFFFFFFFFF

const golden_gamma: Int = 0x9E3779B97F4A7C15

const mix_a: Int = 0xBF58476D1CE4E5B9

const mix_b: Int = 0x94D049BB133111EB

/// Construct a seed from an integer. Negative values are masked to 64 bits.
pub fn seed(value: Int) -> Seed {
  Seed(state: int.bitwise_and(value, mask_64))
}

/// Construct a seed from the system clock. The value is read once and then
/// the seed evolves purely through `split` / `next_int`.
pub fn random_seed() -> Seed {
  Seed(state: int.bitwise_and(now_microseconds(), mask_64))
}

/// Expose the underlying 64-bit state. Useful for serialising into a
/// regression file.
pub fn state(s: Seed) -> Int {
  s.state
}

/// Advance the seed once and return the next 64-bit unsigned integer
/// together with the advanced seed.
pub fn next_int(s: Seed) -> #(Int, Seed) {
  let next_state = int.bitwise_and(s.state + golden_gamma, mask_64)
  let z0 = next_state
  let z1 = mix(int.bitwise_exclusive_or(z0, shift_right(z0, 30)), mix_a)
  let z2 = mix(int.bitwise_exclusive_or(z1, shift_right(z1, 27)), mix_b)
  let z3 = int.bitwise_exclusive_or(z2, shift_right(z2, 31))
  #(z3, Seed(state: next_state))
}

/// Return an integer uniformly in the closed interval `[lo, hi]`.
///
/// If `lo > hi` the bounds are swapped. If `lo == hi` the bound is returned
/// without consuming randomness (the seed is still advanced for determinism).
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
      let positive = int.bitwise_and(raw, 0x7FFFFFFFFFFFFFFF)
      #(low + positive % span, s2)
    }
  }
}

/// Split a seed into two statistically independent seeds.
///
/// Used to give each `Generator` sub-component its own stream so that
/// shrinking one component does not perturb others.
pub fn split(s: Seed) -> #(Seed, Seed) {
  let #(left_state, s1) = next_int(s)
  let #(right_state, _) = next_int(s1)
  #(Seed(state: left_state), Seed(state: right_state))
}

fn mix(value: Int, k: Int) -> Int {
  let product = value * k
  int.bitwise_and(product, mask_64)
}

fn shift_right(value: Int, by: Int) -> Int {
  int.bitwise_shift_right(int.bitwise_and(value, mask_64), by)
}

@external(erlang, "metamon_ffi", "now_microseconds")
@external(javascript, "../../metamon_ffi.mjs", "now_microseconds")
fn now_microseconds() -> Int
