//// Generic shrink helpers used by `metamon/generator` to build
//// `Tree(a)`-shaped values for primitive types. Each helper returns a
//// list of "smaller" candidates that the runner will explore in order.

import gleam/float
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

/// Floats closer to `origin` than `value` and inside `[low, high]`: the
/// origin, the whole number next to `value` on the side of the origin, then
/// `value` minus a half, a quarter and so on of its distance to the origin. Repeating it
/// on the first failing candidate walks to the boundary of the failure,
/// such as `500.0` for `x <. 500.0`.
pub fn float_toward(
  origin: Float,
  value: Float,
  low: Float,
  high: Float,
) -> List(Float) {
  let distance = value -. origin
  // Compared as numbers: on Erlang -0.0 is not `==` to 0.0.
  case is_zero(distance) {
    True -> []
    False -> {
      // Beyond 2^53 every float is already a whole number.
      let whole = case float.absolute_value(value) <. 9.0e15 {
        True if distance >. 0.0 -> [float.floor(value)]
        True -> [float.ceiling(value)]
        False -> []
      }
      [origin, ..list.append(whole, float_halves(value, distance /. 2.0, []))]
      |> list.filter(fn(candidate) {
        candidate >=. low
        && candidate <=. high
        && float.absolute_value(candidate -. origin)
        <. float.absolute_value(distance)
      })
      |> list.unique
    }
  }
}

fn float_halves(value: Float, step: Float, acc: List(Float)) -> List(Float) {
  let candidate = value -. step
  case is_zero(candidate -. value) {
    True -> list.reverse(acc)
    False -> float_halves(value, step /. 2.0, [candidate, ..acc])
  }
}

fn is_zero(x: Float) -> Bool {
  x >=. 0.0 && x <=. 0.0
}
