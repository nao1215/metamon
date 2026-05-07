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
///
/// Panics at construction if `lo > hi`. An inverted pair is almost always
/// a bug (swapped arguments), so failing visibly catches it earlier than
/// silently normalising.
pub fn constant(lo: Int, hi: Int) -> Range {
  let _ = assert_ordered(lo, hi)
  let chosen_origin = case lo <= 0 && 0 <= hi {
    True -> 0
    False -> lo
  }
  Range(origin: chosen_origin, kind: Const(lo: lo, hi: hi))
}

/// A range that scales linearly: at `size = 0` returns `[origin, origin]`
/// and at `size = max_size` returns the full `[lo, hi]`.
///
/// Panics at construction if `lo > hi`.
pub fn linear(lo: Int, hi: Int) -> Range {
  let _ = assert_ordered(lo, hi)
  let chosen_origin = case lo <= 0 && 0 <= hi {
    True -> 0
    False -> lo
  }
  Range(origin: chosen_origin, kind: Linear(lo: lo, hi: hi))
}

/// Like `linear` but the origin is supplied explicitly. Useful when the
/// natural shrink target is not `0` (e.g. years near `2000` shrinking to
/// `2000`).
///
/// Panics at construction if `lo > hi` or if `origin` is outside
/// `[lo, hi]`. An origin outside the interval would silently emit
/// out-of-range values at small sizes (`size = 0` collapses both
/// bounds to `origin`), so failing visibly catches the misuse. This
/// matches the invariant `linear` upholds automatically (its origin
/// is always either `0` when inside the interval, or `lo`).
pub fn linear_from(origin: Int, lo: Int, hi: Int) -> Range {
  let _ = assert_ordered(lo, hi)
  let _ = assert_origin_in_bounds(origin, lo, hi)
  Range(origin: origin, kind: Linear(lo: lo, hi: hi))
}

/// Exponential scaling: bounds grow roughly like `size^2 / max_size`,
/// well-suited for ranges spanning many orders of magnitude.
///
/// Panics at construction if `lo > hi`.
pub fn exponential(lo: Int, hi: Int) -> Range {
  let _ = assert_ordered(lo, hi)
  let chosen_origin = case lo <= 0 && 0 <= hi {
    True -> 0
    False -> lo
  }
  Range(origin: chosen_origin, kind: Exponential(lo: lo, hi: hi))
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

fn assert_ordered(lo: Int, hi: Int) -> Nil {
  case lo > hi {
    True -> panic as "range: lo must be <= hi (got inverted bounds)"
    False -> Nil
  }
}

fn assert_origin_in_bounds(origin: Int, lo: Int, hi: Int) -> Nil {
  case origin < lo || origin > hi {
    True ->
      panic as "range.linear_from: origin must lie inside [lo, hi] (an out-of-range origin would emit values outside the documented interval at small sizes)"
    False -> Nil
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
