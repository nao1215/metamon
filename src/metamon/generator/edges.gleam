//// Default edge values for the built-in generators. These are the
//// "must-try" boundary inputs that the runner consumes before falling
//// back to random generation. Curating a good edge set is the single
//// biggest win for property-based testing on real-world code, so each
//// builder here is documented with the rationale.

/// Edge ints in the closed interval `[lo, hi]`.
///
/// Always-tried candidates: `0`, `1`, `-1`, `lo`, `hi`. We also include
/// "common bug magnets" (`Int.max`, `Int.min`, neighbouring values
/// around 0) when they fall inside the range.
pub fn ints_in(lo: Int, hi: Int) -> List(Int) {
  let candidates = [
    0,
    1,
    -1,
    lo,
    hi,
    lo + 1,
    hi - 1,
    9_223_372_036_854_775_807,
    -9_223_372_036_854_775_808,
  ]
  candidates
  |> filter_in_range(lo, hi)
  |> dedupe()
}

/// Edge floats in `[lo, hi]`.
///
/// Includes `lo`, `hi`, `0.0`, plus IEEE-754 bug magnets where
/// representable: smallest positive subnormal-ish constants are not
/// emitted to keep behaviour identical across BEAM and JS targets.
pub fn floats_in(lo: Float, hi: Float) -> List(Float) {
  let candidates = [lo, hi, 0.0, 1.0, -1.0]
  candidates
  |> filter_floats_in_range(lo, hi)
  |> dedupe_floats()
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
  list_append(strings_ascii(), extras)
}

fn filter_in_range(items: List(Int), lo: Int, hi: Int) -> List(Int) {
  case items {
    [] -> []
    [first, ..rest] ->
      case first >= lo && first <= hi {
        True -> [first, ..filter_in_range(rest, lo, hi)]
        False -> filter_in_range(rest, lo, hi)
      }
  }
}

fn filter_floats_in_range(
  items: List(Float),
  lo: Float,
  hi: Float,
) -> List(Float) {
  case items {
    [] -> []
    [first, ..rest] ->
      case first >=. lo && first <=. hi {
        True -> [first, ..filter_floats_in_range(rest, lo, hi)]
        False -> filter_floats_in_range(rest, lo, hi)
      }
  }
}

fn dedupe(items: List(Int)) -> List(Int) {
  dedupe_loop(items, [], [])
}

fn dedupe_loop(items: List(Int), seen: List(Int), acc: List(Int)) -> List(Int) {
  case items {
    [] -> reverse(acc)
    [first, ..rest] ->
      case contains(seen, first) {
        True -> dedupe_loop(rest, seen, acc)
        False -> dedupe_loop(rest, [first, ..seen], [first, ..acc])
      }
  }
}

fn dedupe_floats(items: List(Float)) -> List(Float) {
  dedupe_floats_loop(items, [], [])
}

fn dedupe_floats_loop(
  items: List(Float),
  seen: List(Float),
  acc: List(Float),
) -> List(Float) {
  case items {
    [] -> reverse(acc)
    [first, ..rest] ->
      case contains_float(seen, first) {
        True -> dedupe_floats_loop(rest, seen, acc)
        False -> dedupe_floats_loop(rest, [first, ..seen], [first, ..acc])
      }
  }
}

fn contains(items: List(Int), needle: Int) -> Bool {
  case items {
    [] -> False
    [first, ..rest] ->
      case first == needle {
        True -> True
        False -> contains(rest, needle)
      }
  }
}

fn contains_float(items: List(Float), needle: Float) -> Bool {
  case items {
    [] -> False
    [first, ..rest] ->
      case first == needle {
        True -> True
        False -> contains_float(rest, needle)
      }
  }
}

fn reverse(items: List(a)) -> List(a) {
  reverse_into(items, [])
}

fn reverse_into(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> reverse_into(rest, [first, ..acc])
  }
}

fn list_append(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [first, ..rest] -> [first, ..list_append(rest, right)]
  }
}
