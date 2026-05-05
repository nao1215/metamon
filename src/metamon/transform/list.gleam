//// Standard `Transform(List(a))` constructors used in metamorphic
//// relations. Each transform is named and deterministic.

import gleam/int
import gleam/list
import metamon/generator/seed.{type Seed}
import metamon/transform.{type Transform}

/// Reverse the list.
pub fn reverse() -> Transform(List(a)) {
  transform.new("list.reverse", list.reverse)
}

/// Drop duplicates, keeping the first occurrence of each element.
pub fn dedupe() -> Transform(List(a)) {
  transform.new("list.dedupe", dedupe_keep_first)
}

fn dedupe_keep_first(items: List(a)) -> List(a) {
  loop_dedupe(items, [], [])
}

fn loop_dedupe(items: List(a), seen: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> list.reverse(acc)
    [first, ..rest] ->
      case list.contains(seen, first) {
        True -> loop_dedupe(rest, seen, acc)
        False -> loop_dedupe(rest, [first, ..seen], [first, ..acc])
      }
  }
}

/// Prepend `value` to the list.
pub fn prepend(value: a) -> Transform(List(a)) {
  transform.new("list.prepend", fn(items) { [value, ..items] })
}

/// Append `value` to the list.
pub fn append(value: a) -> Transform(List(a)) {
  transform.new("list.append", fn(items) { list.append(items, [value]) })
}

/// A deterministic shuffle parametrised by a seed integer. The same
/// integer always produces the same permutation. Implemented as a
/// stable sort by random keys (Knuth's "decorate, sort, undecorate"
/// pattern).
pub fn shuffle(seed_value: Int) -> Transform(List(a)) {
  transform.new("list.shuffle(" <> int.to_string(seed_value) <> ")", fn(items) {
    shuffle_with(items, seed.seed(seed_value))
  })
}

fn shuffle_with(items: List(a), s: Seed) -> List(a) {
  let length = list.length(items)
  case length <= 1 {
    True -> items
    False -> assign_keys_and_sort(items, s, length)
  }
}

fn assign_keys_and_sort(items: List(a), s: Seed, length: Int) -> List(a) {
  let keyed =
    list.fold(items, #(s, []), fn(acc, value) {
      let #(state, keyed_acc) = acc
      let #(key, next_state) = seed.next_int_in(state, 0, length * 100)
      #(next_state, [#(key, value), ..keyed_acc])
    })
  let #(_, with_keys) = keyed
  with_keys
  |> list.sort(by: fn(left, right) { int.compare(left.0, right.0) })
  |> list.map(fn(pair) { pair.1 })
}
