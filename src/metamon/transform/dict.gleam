//// Standard `Transform(Dict(k, v))` constructors used in metamorphic
//// relations. The classic use case is asserting that a function is
//// invariant under key reordering: `f(shuffle_keys(d)) == f(d)`.

import gleam/dict.{type Dict}
import gleam/int
import metamon/transform.{type Transform}
import metamon/transform/list as list_t

/// Insert / overwrite the binding `key -> value`.
pub fn insert(key: k, value: v) -> Transform(Dict(k, v)) {
  transform.new("dict.insert", fn(d) { dict.insert(d, key, value) })
}

/// Delete `key` from the dict if present.
pub fn remove(key: k) -> Transform(Dict(k, v)) {
  transform.new("dict.remove", fn(d) { dict.delete(d, key) })
}

/// Re-insert all entries in a deterministically shuffled order. The
/// resulting dict is `==`-equal to the input (since `Dict` ignores
/// insertion order), but any consumer that observes traversal order
/// will see a different sequence — exactly the property metamorphic
/// tests want to catch.
pub fn shuffle_keys(seed_value: Int) -> Transform(Dict(k, v)) {
  let shuffle = list_t.shuffle(seed_value)
  transform.new("dict.shuffle_keys(" <> int.to_string(seed_value) <> ")", fn(d) {
    dict.to_list(d) |> shuffle.apply |> dict.from_list
  })
}
