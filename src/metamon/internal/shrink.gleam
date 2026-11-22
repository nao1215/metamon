//// Generic shrink helpers used by `metamon/generator` to build
//// `Tree(a)`-shaped values for primitive types. Each helper returns a
//// list of "smaller" candidates that the runner will explore in order.

import gleam/list

/// Halve `value` toward `origin`. Returns the empty list when no
/// further progress is possible (e.g. value already equals origin).
///
/// The classic QuickCheck-style shrink: try the origin first, then
/// progressively closer-to-`value` candidates. For example,
/// `int_toward(0, 64)` yields `[0, 32, 48, 56, 60, 62, 63]`. The
/// runner walks this list in order, so the smallest counter-example
/// is found in a single step when `origin` itself triggers the bug.
pub fn int_toward(origin: Int, value: Int) -> List(Int) {
  case value == origin {
    True -> []
    False -> {
      let diff = value - origin
      compute_halves(diff)
      |> list.map(fn(h) { value - h })
      |> list.unique
    }
  }
}

fn compute_halves(n: Int) -> List(Int) {
  case n == 0 {
    True -> []
    False -> [n, ..compute_halves(n / 2)]
  }
}
