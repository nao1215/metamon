//// Named two-argument predicates used by metamorphic relations.
////
//// A `Relation(b)` answers "do these two outputs satisfy the
//// constraint?". The `name` is surfaced in failure reports so the
//// user immediately sees which property broke.

import gleam/float
import gleam/list
import gleam/order

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

/// Inequality.
pub fn not_equal() -> Relation(a) {
  Relation(name: "not_equal", holds: fn(left, right) { left != right })
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

/// `left` is a sub-multiset of `right`.
pub fn subset_of() -> Relation(List(a)) {
  Relation(name: "subset_of", holds: fn(left, right) { is_subset(left, right) })
}

fn is_subset(left: List(a), right: List(a)) -> Bool {
  case left {
    [] -> True
    [first, ..rest] ->
      case remove_one(first, right) {
        Ok(remaining) -> is_subset(rest, remaining)
        Error(_) -> False
      }
  }
}

/// `cmp(left, right)` returns `Lt` or `Eq` (i.e. left ≤ right).
pub fn monotone(cmp: fn(a, a) -> order.Order) -> Relation(a) {
  Relation(name: "monotone", holds: fn(left, right) {
    case cmp(left, right) {
      order.Lt -> True
      order.Eq -> True
      order.Gt -> False
    }
  })
}

/// Conditional relation: if `antecedent(left, right)` is `True`, the
/// inner relation must hold. Otherwise the relation is trivially
/// satisfied.
pub fn implies(antecedent: fn(b, b) -> Bool, inner: Relation(b)) -> Relation(b) {
  Relation(name: "implies(" <> inner.name <> ")", holds: fn(left, right) {
    case antecedent(left, right) {
      False -> True
      True -> inner.holds(left, right)
    }
  })
}

/// Both `r1` and `r2` must hold.
pub fn and(r1: Relation(b), r2: Relation(b)) -> Relation(b) {
  Relation(name: r1.name <> " and " <> r2.name, holds: fn(left, right) {
    r1.holds(left, right) && r2.holds(left, right)
  })
}

/// At least one of `r1` and `r2` must hold.
pub fn or(r1: Relation(b), r2: Relation(b)) -> Relation(b) {
  Relation(name: r1.name <> " or " <> r2.name, holds: fn(left, right) {
    r1.holds(left, right) || r2.holds(left, right)
  })
}

/// Negate a relation.
pub fn invert(r: Relation(b)) -> Relation(b) {
  Relation(name: "not(" <> r.name <> ")", holds: fn(left, right) {
    !r.holds(left, right)
  })
}

/// Override a relation's name.
pub fn rename(r: Relation(b), name: String) -> Relation(b) {
  Relation(name: name, holds: r.holds)
}

// ---------- N-ary relations ----------

/// A relation across an arbitrary number of follow-up outputs.
/// `holds(outputs)` receives the source output as `outputs[0]` and
/// the i-th follow-up output as `outputs[i + 1]`. Used by
/// `metamon.forall_morph_n` for MRs that compare more than two
/// outputs (e.g. `f(x), f(T1(x)), f(T2(x))` are pairwise equal).
pub type RelationN(b) {
  RelationN(name: String, holds: fn(List(b)) -> Bool)
}

/// Construct an N-ary relation directly.
pub fn n_new(name: String, holds: fn(List(b)) -> Bool) -> RelationN(b) {
  RelationN(name: name, holds: holds)
}

/// All elements of the input list are equal under structural `==`.
/// Trivially `True` for lists of length 0 or 1.
pub fn all_equal() -> RelationN(b) {
  RelationN(name: "all_equal", holds: fn(items) { all_equal_loop(items) })
}

fn all_equal_loop(items: List(b)) -> Bool {
  case items {
    [] -> True
    [_] -> True
    [first, second, ..rest] ->
      case first == second {
        True -> all_equal_loop([second, ..rest])
        False -> False
      }
  }
}

/// Lift a binary `Relation(b)` to an N-ary relation by checking it
/// pairwise: every consecutive pair `(items[i], items[i+1])` must
/// satisfy `r`. For `name == "equal"` this gives a chain of equal
/// values; for `monotone` it gives a sorted chain.
pub fn pairwise(r: Relation(b)) -> RelationN(b) {
  RelationN(name: "pairwise(" <> r.name <> ")", holds: fn(items) {
    pairwise_loop(r, items)
  })
}

fn pairwise_loop(r: Relation(b), items: List(b)) -> Bool {
  case items {
    [] -> True
    [_] -> True
    [first, second, ..rest] ->
      case r.holds(first, second) {
        True -> pairwise_loop(r, [second, ..rest])
        False -> False
      }
  }
}
