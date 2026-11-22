//// The integer interval behind `generator.Range`: its bounds, how they
//// grow with the size, and the origin values shrink toward.

/// How the bounds of an interval follow the size.
pub type Scaling {
  /// The bounds are `[lo, hi]` at every size.
  Constant
  /// The bounds grow linearly from `[origin, origin]` at size 0 to
  /// `[lo, hi]` at the largest size.
  Linear
}

/// A closed interval `[lo, hi]` with `lo <= hi` and `lo <= origin <= hi`.
pub type Interval {
  Interval(lo: Int, hi: Int, origin: Int, scaling: Scaling)
}

/// The interval between `from` and `to`, in either order. The origin is
/// `0` when `0` lies inside, otherwise the lower bound.
pub fn new(from: Int, to: Int, scaling: Scaling) -> Interval {
  let #(lo, hi) = case from > to {
    True -> #(to, from)
    False -> #(from, to)
  }
  let origin = case lo <= 0 && 0 <= hi {
    True -> 0
    False -> lo
  }
  Interval(lo: lo, hi: hi, origin: origin, scaling: scaling)
}

/// The `[lo, hi]` bounds at `size`, clamped into `[0, max_size]`.
pub fn bounds(interval: Interval, size: Int, max_size: Int) -> #(Int, Int) {
  case interval.scaling {
    Constant -> #(interval.lo, interval.hi)
    Linear -> {
      let max_size = case max_size <= 0 {
        True -> 1
        False -> max_size
      }
      let size = case size < 0, size > max_size {
        True, _ -> 0
        _, True -> max_size
        _, _ -> size
      }
      let scale = fn(bound) {
        interval.origin + { bound - interval.origin } * size / max_size
      }
      #(scale(interval.lo), scale(interval.hi))
    }
  }
}
