//// FFI-only wrapper that exposes the IEEE 754 special float constants
//// (NaN, ±Infinity, smallest positive denormal, largest finite) used by
//// `generator.float_special`.
////
//// Target asymmetry: the JavaScript target returns genuine non-finite
//// values via `Number.{NaN, POSITIVE_INFINITY, NEGATIVE_INFINITY,
//// MIN_VALUE, MAX_VALUE}`. The Erlang/BEAM target cannot construct
//// non-finite doubles from pure Erlang — every public conversion path
//// (`<<F/float>>` pattern, `binary_to_term/1` with NEW_FLOAT_EXT,
//// `binary_to_float/1`) refuses NaN and ±Infinity bit patterns. The
//// BEAM FFI therefore substitutes finite sentinels: `nan()` and
//// `positive_infinity()` return the largest finite double,
//// `negative_infinity()` returns its negation. Properties that depend
//// on genuine non-finite values must run on the JavaScript target.

@external(erlang, "metamon_ffi", "ieee_nan")
@external(javascript, "../../metamon_ffi.mjs", "ieee_nan")
pub fn nan() -> Float

@external(erlang, "metamon_ffi", "ieee_positive_infinity")
@external(javascript, "../../metamon_ffi.mjs", "ieee_positive_infinity")
pub fn positive_infinity() -> Float

@external(erlang, "metamon_ffi", "ieee_negative_infinity")
@external(javascript, "../../metamon_ffi.mjs", "ieee_negative_infinity")
pub fn negative_infinity() -> Float

@external(erlang, "metamon_ffi", "ieee_smallest_positive_denormal")
@external(javascript, "../../metamon_ffi.mjs", "ieee_smallest_positive_denormal")
pub fn smallest_positive_denormal() -> Float

@external(erlang, "metamon_ffi", "ieee_largest_finite")
@external(javascript, "../../metamon_ffi.mjs", "ieee_largest_finite")
pub fn largest_finite() -> Float
