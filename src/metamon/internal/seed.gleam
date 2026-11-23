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
/// runs; CI should pin a value with `Config(..default_config(), seed: Some(n))`.
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
/// `state/1` to decide whether to show the configured seed.
pub fn original_input(s: Seed) -> Option(Int) {
  s.original_input
}

/// Advance the seed once and return the next non-negative integer
/// alongside the advanced seed.
fn next_int(s: Seed) -> #(Int, Seed) {
  let next_state = step(s.state)
  #(next_state, Seed(state: next_state, original_input: None))
}

/// Return an integer uniformly in the closed interval `[lo, hi]`.
///
/// If `lo > hi` the bounds are swapped. If `lo == hi` the bound is
/// returned without consuming randomness (the seed is still advanced
/// for determinism).
///
/// A span of up to 2^16 values reduces one 32-bit draw, which is uniform
/// to within 1 part in 65536. A wider span draws 53 bits and rejects the
/// draws past the largest multiple of the span, so every value is equally
/// likely and both targets compute the same value exactly. Spans beyond
/// 2^53, which only Erlang holds exactly, add 32-bit draws until there
/// are 32 bits to spare.
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
      let span = high - low + 1
      let #(offset, s2) = case span <= one_word_span {
        True -> {
          let #(raw, s2) = next_int(s)
          #(raw % span, s2)
        }
        False ->
          case span - 1 <= max_safe_integer {
            True -> uniform_below(s, span)
            False -> wide_draw(s, span, 0, 1)
          }
      }
      #(low + offset, s2)
    }
  }
}

/// The widest span reduced from a single 32-bit draw.
const one_word_span: Int = 0x10000

/// 2^53 - 1, the largest integer JavaScript holds exactly.
const max_safe_integer: Int = 9_007_199_254_740_991

/// A 53-bit draw: 21 bits of one word above the 32 bits of the next.
fn draw_53_bits(s: Seed) -> #(Int, Seed) {
  let #(high, s1) = next_int(s)
  let #(low, s2) = next_int(s1)
  #(high % 0x200000 * 0x100000000 + low, s2)
}

/// A value in `[0, span)` for `span <= 2^53`, by rejection: draws at or past
/// the largest multiple of `span` below 2^53 are drawn again.
fn uniform_below(s: Seed, span: Int) -> #(Int, Seed) {
  let limit = max_safe_integer - { max_safe_integer % span + 1 } % span
  let #(raw, s2) = draw_53_bits(s)
  case raw <= limit {
    True -> #(raw % span, s2)
    False -> uniform_below(s2, span)
  }
}

fn wide_draw(s: Seed, span: Int, acc: Int, bound: Int) -> #(Int, Seed) {
  case bound / 0x100000000 >= span {
    True -> #(acc % span, s)
    False -> {
      let #(word, s2) = next_int(s)
      wide_draw(s2, span, acc * 0x100000000 + word, bound * 0x100000000)
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

// Every 32-bit chunk of the magnitude is folded in, and a negative value
// flips the top bit, so `seed(-n)` and `seed(n + 2^32)` differ from
// `seed(n)`. A fold of 0 is replaced by the default state.
fn normalise(value: Int) -> Int {
  let folded = case value < 0 {
    True -> int.bitwise_exclusive_or(fold_chunks(0 - value, 0), 0x80000000)
    False -> fold_chunks(value, 0)
  }
  case folded {
    0 -> default_state
    n -> n
  }
}

fn fold_chunks(value: Int, acc: Int) -> Int {
  case value {
    0 -> acc
    _ ->
      fold_chunks(
        value / 0x100000000,
        int.bitwise_exclusive_or(acc, value % 0x100000000),
      )
  }
}

@external(erlang, "metamon_ffi", "now_microseconds")
@external(javascript, "../../metamon_ffi.mjs", "now_microseconds")
fn now_microseconds() -> Int
