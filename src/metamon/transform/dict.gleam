//// Standard `Transform(Dict(k, v))` constructors used in metamorphic
//// relations. The classic use case is asserting that a function is
//// invariant under key reordering: `f(shuffle_keys(d)) == f(d)`.

import gleam/dict.{type Dict}
import gleam/int
import metamon/generator/seed.{type Seed}
import metamon/transform.{type Transform}

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
  transform.new("dict.shuffle_keys(" <> int.to_string(seed_value) <> ")", fn(d) {
    reorder_dict(d, seed.seed(seed_value))
  })
}

fn reorder_dict(d: Dict(k, v), s: Seed) -> Dict(k, v) {
  let pairs = dict.to_list(d)
  let length = list_length(pairs)
  case length <= 1 {
    True -> d
    False -> {
      let shuffled = assign_keys_and_sort(pairs, s, length)
      dict.from_list(shuffled)
    }
  }
}

fn assign_keys_and_sort(
  pairs: List(#(k, v)),
  s: Seed,
  length: Int,
) -> List(#(k, v)) {
  let folded = fold_assign_keys(pairs, s, length, [])
  let #(_, with_keys) = folded
  with_keys
  |> sort_by_first_int()
  |> drop_first_int()
}

fn fold_assign_keys(
  pairs: List(#(k, v)),
  s: Seed,
  length: Int,
  acc: List(#(Int, #(k, v))),
) -> #(Seed, List(#(Int, #(k, v)))) {
  case pairs {
    [] -> #(s, acc)
    [first, ..rest] -> {
      let #(key, next_state) = seed.next_int_in(s, 0, length * 100)
      fold_assign_keys(rest, next_state, length, [#(key, first), ..acc])
    }
  }
}

fn list_length(items: List(a)) -> Int {
  count(items, 0)
}

fn count(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> count(rest, acc + 1)
  }
}

fn sort_by_first_int(items: List(#(Int, a))) -> List(#(Int, a)) {
  // Insertion sort; small N, simple, no stdlib dependency on `list.sort`.
  case items {
    [] -> []
    [first, ..rest] -> insert_sorted(first, sort_by_first_int(rest))
  }
}

fn insert_sorted(item: #(Int, a), sorted: List(#(Int, a))) -> List(#(Int, a)) {
  case sorted {
    [] -> [item]
    [first, ..rest] ->
      case item.0 <= first.0 {
        True -> [item, first, ..rest]
        False -> [first, ..insert_sorted(item, rest)]
      }
  }
}

fn drop_first_int(items: List(#(Int, a))) -> List(a) {
  case items {
    [] -> []
    [first, ..rest] -> [first.1, ..drop_first_int(rest)]
  }
}
