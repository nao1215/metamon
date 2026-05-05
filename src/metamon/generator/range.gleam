//// Bounds + shrink origin + size scaling for numeric generators.
////
//// A `Range(Int)` describes how a generator's bounds widen as the test
//// `size` parameter grows from 0 (smallest) toward `max_size`, and where
//// shrinking should converge ("origin"). Modelled on Hedgehog's `Range`.

/// Internal kind used to compute size-dependent bounds.
type Kind {
  /// Constant bounds, no scaling with size.
  Const(lo: Int, hi: Int)
  /// Linear scaling between origin and bounds.
  Linear(lo: Int, hi: Int)
  /// Exponential scaling (rough doubling per size step) toward bounds.
  Exponential(lo: Int, hi: Int)
}

/// Closed integer interval with a shrink origin and a size-dependent
/// growth strategy.
pub opaque type Range {
  Range(origin: Int, kind: Kind)
}

/// A range that always returns exactly `value`.
pub fn singleton(value: Int) -> Range {
  Range(origin: value, kind: Const(lo: value, hi: value))
}

/// A range that ignores `size` and always uses `[lo, hi]`. Origin is `lo`
/// (or `0` if `0` lies inside the interval, which usually shrinks better).
pub fn constant(lo: Int, hi: Int) -> Range {
  let #(low, high) = order_pair(lo, hi)
  let chosen_origin = case low <= 0 && 0 <= high {
    True -> 0
    False -> low
  }
  Range(origin: chosen_origin, kind: Const(lo: low, hi: high))
}

/// A range that scales linearly: at `size = 0` returns `[origin, origin]`
/// and at `size = max_size` returns the full `[lo, hi]`.
pub fn linear(lo: Int, hi: Int) -> Range {
  let #(low, high) = order_pair(lo, hi)
  let chosen_origin = case low <= 0 && 0 <= high {
    True -> 0
    False -> low
  }
  Range(origin: chosen_origin, kind: Linear(lo: low, hi: high))
}

/// Like `linear` but the origin is supplied explicitly. Useful when the
/// natural shrink target is not `0` (e.g. years near `2000` shrinking to
/// `2000`).
pub fn linear_from(origin: Int, lo: Int, hi: Int) -> Range {
  let #(low, high) = order_pair(lo, hi)
  Range(origin: origin, kind: Linear(lo: low, hi: high))
}

/// Exponential scaling: bounds grow roughly like `size^2 / max_size`,
/// well-suited for ranges spanning many orders of magnitude.
pub fn exponential(lo: Int, hi: Int) -> Range {
  let #(low, high) = order_pair(lo, hi)
  let chosen_origin = case low <= 0 && 0 <= high {
    True -> 0
    False -> low
  }
  Range(origin: chosen_origin, kind: Exponential(lo: low, hi: high))
}

/// The shrink target for this range.
pub fn origin(range: Range) -> Int {
  range.origin
}

/// Compute the actual `[lo, hi]` bounds for a given `size` between `0`
/// and `max_size`. `size` is clamped into `[0, max_size]`.
pub fn bounds(range: Range, size: Int, max_size: Int) -> #(Int, Int) {
  let max_size = case max_size <= 0 {
    True -> 1
    False -> max_size
  }
  let clamped_size = clamp(size, 0, max_size)
  case range.kind {
    Const(lo, hi) -> #(lo, hi)
    Linear(lo, hi) -> {
      let lo_scaled = scale_linear(range.origin, lo, clamped_size, max_size)
      let hi_scaled = scale_linear(range.origin, hi, clamped_size, max_size)
      #(lo_scaled, hi_scaled)
    }
    Exponential(lo, hi) -> {
      let lo_scaled =
        scale_exponential(range.origin, lo, clamped_size, max_size)
      let hi_scaled =
        scale_exponential(range.origin, hi, clamped_size, max_size)
      #(lo_scaled, hi_scaled)
    }
  }
}

fn order_pair(left: Int, right: Int) -> #(Int, Int) {
  case left > right {
    True -> #(right, left)
    False -> #(left, right)
  }
}

fn clamp(value: Int, lo: Int, hi: Int) -> Int {
  case value < lo, value > hi {
    True, _ -> lo
    _, True -> hi
    _, _ -> value
  }
}

fn scale_linear(origin: Int, bound: Int, size: Int, max_size: Int) -> Int {
  let delta = bound - origin
  origin + delta * size / max_size
}

fn scale_exponential(origin: Int, bound: Int, size: Int, max_size: Int) -> Int {
  let delta = bound - origin
  origin + delta * size * size / { max_size * max_size }
}
