//// Named two-argument predicates used by metamorphic relations.
////
//// A `Relation(b)` answers "do these two outputs satisfy the
//// constraint?". The `name` is surfaced in failure reports so the
//// user immediately sees which property broke.

import gleam/float
import gleam/list

/// A named two-argument predicate over outputs.
pub type Relation(b) {
  Relation(name: String, holds: fn(b, b) -> Bool)
}

/// Construct a relation from a name and a binary predicate.
pub fn new(name: String, holds: fn(b, b) -> Bool) -> Relation(b) {
  Relation(name: name, holds: holds)
}

/// Equality (Gleam's structural `==`).
pub fn equal() -> Relation(a) {
  Relation(name: "equal", holds: fn(left, right) { left == right })
}

/// Equality after a shared normalisation step. Useful for
/// "equal modulo whitespace / key order / formatting".
pub fn equivalent_under(via: fn(b) -> c, name: String) -> Relation(b) {
  Relation(name: "equivalent_under(" <> name <> ")", holds: fn(left, right) {
    via(left) == via(right)
  })
}

/// Floats within `epsilon` of each other.
///
/// Panics at construction if `epsilon` is negative. A negative epsilon
/// would silently yield a degenerate "always false" relation (the
/// absolute difference is always non-negative, so `diff <=. epsilon`
/// can never hold). Failing visibly on a sign mistake matches the
/// project's posture for malformed numeric inputs in `Range.constant`,
/// `Range.linear`, etc.
pub fn approximately(epsilon: Float) -> Relation(Float) {
  case epsilon <. 0.0 {
    True ->
      panic as "metamon.approximately: epsilon must be >= 0.0 (a negative epsilon would make every pair compare False, including a value with itself)"
    False ->
      Relation(
        name: "approximately(" <> float.to_string(epsilon) <> ")",
        holds: fn(left, right) {
          let diff = case left >=. right {
            True -> left -. right
            False -> right -. left
          }
          diff <=. epsilon
        },
      )
  }
}

/// Two lists are permutations of each other (same multiset).
pub fn permutation_of() -> Relation(List(a)) {
  Relation(name: "permutation_of", holds: is_permutation)
}

fn is_permutation(left: List(a), right: List(a)) -> Bool {
  case list.length(left) == list.length(right) {
    False -> False
    True -> remove_each(left, right) == []
  }
}

fn remove_each(to_remove: List(a), remaining: List(a)) -> List(a) {
  case to_remove {
    [] -> remaining
    [first, ..rest] ->
      case remove_one(first, remaining) {
        Ok(remaining_after) -> remove_each(rest, remaining_after)
        Error(_) -> [first]
        // Mismatch — return non-empty so the caller sees inequality.
      }
  }
}

fn remove_one(target: a, items: List(a)) -> Result(List(a), Nil) {
  remove_one_loop(target, items, [])
}

fn remove_one_loop(
  target: a,
  items: List(a),
  acc: List(a),
) -> Result(List(a), Nil) {
  case items {
    [] -> Error(Nil)
    [first, ..rest] ->
      case first == target {
        True -> Ok(list.append(list.reverse(acc), rest))
        False -> remove_one_loop(target, rest, [first, ..acc])
      }
  }
}
