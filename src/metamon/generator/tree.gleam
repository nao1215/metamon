//// A lazy rose tree: a value paired with an on-demand stream of "smaller"
//// alternatives. Generators in metamon return `Tree(a)` instead of bare
//// values so shrinking is always available without separate plumbing.
////
//// The lazy stream type `Shrinks(a)` is defined locally instead of using
//// an external lazy-list library, keeping metamon's runtime dependencies
//// limited to `gleam_stdlib`.

import gleam/list

/// A lazy stream of shrink alternatives.
///
/// Each element is computed on demand by forcing `step`; once a `Done`
/// step is observed the stream is exhausted. `Shrinks(a)` is functorial
/// (`map_shrinks`), filterable (`filter_shrinks`), and concatenable
/// (`append_shrinks`).
pub opaque type Shrinks(a) {
  Shrinks(step: fn() -> ShrinkStep(a))
}

/// One step in a `Shrinks(a)` stream.
pub type ShrinkStep(a) {
  Done
  More(head: a, tail: Shrinks(a))
}

/// A value and its lazy shrink alternatives.
///
/// Each `Tree(a)` represents a single generated value (`value`) and a
/// stream of smaller candidate trees (`shrinks`). The runner walks
/// `shrinks` only when a property has failed.
pub type Tree(a) {
  Tree(value: a, shrinks: Shrinks(Tree(a)))
}

/// An empty shrink stream.
pub fn no_shrinks() -> Shrinks(a) {
  Shrinks(step: fn() { Done })
}

/// Build a `Shrinks(a)` from a list. Useful when the shrink alternatives
/// are statically known (e.g. integer halving).
pub fn shrinks_from_list(items: List(a)) -> Shrinks(a) {
  case items {
    [] -> Shrinks(step: fn() { Done })
    [first, ..rest] ->
      Shrinks(step: fn() { More(head: first, tail: shrinks_from_list(rest)) })
  }
}

/// Map a function over every element of a `Shrinks(a)` lazily.
pub fn map_shrinks(stream: Shrinks(a), f: fn(a) -> b) -> Shrinks(b) {
  Shrinks(step: fn() {
    case stream.step() {
      Done -> Done
      More(head, tail) -> More(head: f(head), tail: map_shrinks(tail, f))
    }
  })
}

/// Concatenate two `Shrinks(a)` streams. The right side is only consulted
/// once the left is exhausted.
pub fn append_shrinks(left: Shrinks(a), right: Shrinks(a)) -> Shrinks(a) {
  Shrinks(step: fn() {
    case left.step() {
      Done -> right.step()
      More(head, tail) -> More(head: head, tail: append_shrinks(tail, right))
    }
  })
}

/// Lazily drop elements that fail `predicate`.
pub fn filter_shrinks(
  stream: Shrinks(a),
  predicate: fn(a) -> Bool,
) -> Shrinks(a) {
  Shrinks(step: fn() { filter_step(stream, predicate) })
}

fn filter_step(stream: Shrinks(a), predicate: fn(a) -> Bool) -> ShrinkStep(a) {
  case stream.step() {
    Done -> Done
    More(head, tail) ->
      case predicate(head) {
        True -> More(head: head, tail: filter_shrinks(tail, predicate))
        False -> filter_step(tail, predicate)
      }
  }
}

/// Force the first `n` elements of a stream into a list.
pub fn shrinks_take(stream: Shrinks(a), n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False ->
      case stream.step() {
        Done -> []
        More(head, tail) -> [head, ..shrinks_take(tail, n - 1)]
      }
  }
}

/// Force the entire stream into a list. Use only on streams known to be
/// finite — generator shrink streams generally are, but be careful with
/// infinite expansions.
pub fn shrinks_to_list(stream: Shrinks(a)) -> List(a) {
  case stream.step() {
    Done -> []
    More(head, tail) -> [head, ..shrinks_to_list(tail)]
  }
}

/// Find the first element satisfying `predicate`, or `Error(Nil)` if no
/// such element exists in the (finite) stream.
pub fn shrinks_find(
  stream: Shrinks(a),
  predicate: fn(a) -> Bool,
) -> Result(a, Nil) {
  case stream.step() {
    Done -> Error(Nil)
    More(head, tail) ->
      case predicate(head) {
        True -> Ok(head)
        False -> shrinks_find(tail, predicate)
      }
  }
}

/// A leaf tree with no shrink alternatives.
pub fn singleton(value: a) -> Tree(a) {
  Tree(value: value, shrinks: no_shrinks())
}

/// Build a tree from a value and an `expand` function that produces direct
/// child values. Each child is recursively expanded with the same function.
pub fn unfold(value: a, expand: fn(a) -> List(a)) -> Tree(a) {
  Tree(
    value: value,
    shrinks: shrinks_from_list(expand(value))
      |> map_shrinks(unfold(_, expand)),
  )
}

/// Build a tree from a value and a pre-computed list of sub-trees.
pub fn from_list(value: a, shrinks: List(Tree(a))) -> Tree(a) {
  Tree(value: value, shrinks: shrinks_from_list(shrinks))
}

/// Map a function over every value in the tree, preserving the shrink
/// structure.
pub fn map(tree: Tree(a), f: fn(a) -> b) -> Tree(b) {
  Tree(value: f(tree.value), shrinks: map_shrinks(tree.shrinks, map(_, f)))
}

/// Monadic bind. Each value's continuation produces its own tree, and the
/// returned tree shrinks both the outer (via the original shrinks) and
/// the inner (via the continuation tree's shrinks). Outer shrinks come
/// first to prefer simplifying the seed-driven structure before rerunning
/// the continuation.
pub fn bind(tree: Tree(a), k: fn(a) -> Tree(b)) -> Tree(b) {
  let inner = k(tree.value)
  let outer_shrinks = map_shrinks(tree.shrinks, bind(_, k))
  Tree(
    value: inner.value,
    shrinks: append_shrinks(outer_shrinks, inner.shrinks),
  )
}

/// Drop tree nodes that fail `predicate`. The root is assumed to satisfy
/// the predicate (callers must ensure this; otherwise the result has no
/// meaningful "current value").
pub fn filter(tree: Tree(a), predicate: fn(a) -> Bool) -> Tree(a) {
  let kept_shrinks =
    tree.shrinks
    |> filter_shrinks(fn(child: Tree(a)) { predicate(child.value) })
    |> map_shrinks(filter(_, predicate))
  Tree(value: tree.value, shrinks: kept_shrinks)
}

/// Combine two trees pairwise. Used to give independent generators a clean
/// product shrink: shrink the left first, then the right. This preserves
/// the "shrink one component while holding the other" property that makes
/// counter-examples easier to read.
pub fn zip(left: Tree(a), right: Tree(b)) -> Tree(#(a, b)) {
  let left_shrinks = map_shrinks(left.shrinks, fn(l) { zip(l, right) })
  let right_shrinks = map_shrinks(right.shrinks, fn(r) { zip(left, r) })
  Tree(
    value: #(left.value, right.value),
    shrinks: append_shrinks(left_shrinks, right_shrinks),
  )
}

/// Force the tree into a list of values up to `depth` levels deep, taking
/// at most `breadth` shrinks per level. Used for inspection in tests.
pub fn outline(tree: Tree(a), depth: Int, breadth: Int) -> List(a) {
  case depth <= 0 {
    True -> [tree.value]
    False -> {
      let direct = shrinks_take(tree.shrinks, breadth)
      let nested =
        list.flat_map(direct, fn(child) { outline(child, depth - 1, breadth) })
      [tree.value, ..nested]
    }
  }
}
