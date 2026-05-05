//// Standard `Transform(String)` constructors used in metamorphic
//// relations.

import gleam/string
import metamon/transform.{type Transform}

/// Reverse the string by graphemes.
pub fn reverse() -> Transform(String) {
  transform.new("string.reverse", string.reverse)
}

/// Lowercase the string (locale-independent ASCII only — gleam_stdlib
/// guarantees ASCII semantics).
pub fn lowercase() -> Transform(String) {
  transform.new("string.lowercase", string.lowercase)
}

/// Uppercase the string (ASCII only — see `lowercase` note).
pub fn uppercase() -> Transform(String) {
  transform.new("string.uppercase", string.uppercase)
}

/// Strip leading and trailing whitespace.
pub fn trim() -> Transform(String) {
  transform.new("string.trim", string.trim)
}

/// Prepend `prefix` to the string.
pub fn prepend(prefix: String) -> Transform(String) {
  transform.new("string.prepend(\"" <> prefix <> "\")", fn(s) { prefix <> s })
}

/// Append `suffix` to the string.
pub fn append(suffix: String) -> Transform(String) {
  transform.new("string.append(\"" <> suffix <> "\")", fn(s) { s <> suffix })
}
