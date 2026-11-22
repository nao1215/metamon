//// Default edge values for the built-in generators. These are the
//// "must-try" boundary inputs that the runner consumes before falling
//// back to random generation. Curating a good edge set is the single
//// biggest win for property-based testing on real-world code, so each
//// builder here is documented with the rationale.

import gleam/list

/// Edge ints in the closed interval `[lo, hi]`.
///
/// Always-tried candidates: `0`, `1`, `-1`, `lo`, `hi`. We also include
/// "common bug magnets" (`Int.max`, `Int.min`, neighbouring values
/// around 0) when they fall inside the range.
pub fn ints_in(lo: Int, hi: Int) -> List(Int) {
  // The "huge" candidates are the JavaScript safe-integer extremes
  // (`±(2^53 - 1)`). The BEAM has arbitrary-precision integers, but
  // we keep the catalogue identical across targets so generated edge
  // sets are reproducible regardless of the runtime.
  let candidates = [
    0,
    1,
    -1,
    lo,
    hi,
    lo + 1,
    hi - 1,
    9_007_199_254_740_991,
    -9_007_199_254_740_991,
  ]
  candidates
  |> list.filter(fn(n) { n >= lo && n <= hi })
  |> list.unique
}

/// Edge floats in `[lo, hi]`.
///
/// Includes `lo`, `hi`, `0.0`, plus IEEE-754 bug magnets where
/// representable: smallest positive subnormal-ish constants are not
/// emitted to keep behaviour identical across BEAM and JS targets.
pub fn floats_in(lo: Float, hi: Float) -> List(Float) {
  let candidates = [lo, hi, 0.0, 1.0, -1.0]
  candidates
  |> list.filter(fn(x) { x >=. lo && x <=. hi })
  |> list.unique
}

/// Edge ASCII strings.
///
/// Empty, single-space, single-tab, single-newline, common short
/// fragments that frequently break tokenisers and Gleam-identifier
/// generators (keywords, leading digit, plus/minus prefix).
pub fn strings_ascii() -> List(String) {
  [
    "",
    " ",
    "\t",
    "\n",
    "0",
    "a",
    "A",
    "_",
    "+1",
    "-1",
    "Type",
    "case",
    "fn",
    "OAuth2Token",
    "256sha",
    "ipv4",
    "null",
  ]
}

/// Edge Unicode-aware strings.
///
/// Adds RTL/BiDi, an emoji, and U+0000 (NUL) which routinely breaks
/// C-FFI bridges. Surrogate halves are intentionally not emitted —
/// they are not valid Gleam strings.
pub fn strings_unicode() -> List(String) {
  let extras = [
    "\u{0000}",
    "\u{200E}helloworld",
    "héllo",
    "𝕏 unicode",
    "🦊",
  ]
  list.append(strings_ascii(), extras)
}
