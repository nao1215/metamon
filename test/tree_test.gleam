import gleam/list
import gleeunit/should
import metamon/internal/tree.{type Shrinks, Done, More}

/// Force a whole shrink stream into a list.
fn to_list(stream: Shrinks(a)) -> List(a) {
  case stream.step() {
    Done -> []
    More(head, tail) -> [head, ..to_list(tail)]
  }
}

/// Every value in the tree, depth first.
fn all_values(t: tree.Tree(a)) -> List(a) {
  [t.value, ..list.flat_map(to_list(t.shrinks), all_values)]
}

fn shrink_int_toward_zero(value: Int) -> List(Int) {
  case value {
    0 -> []
    _ -> [value / 2]
  }
}

pub fn singleton_has_no_shrinks_test() {
  let t = tree.singleton(42)
  should.equal(t.value, 42)
  should.equal(to_list(t.shrinks), [])
}

pub fn unfold_uses_expand_recursively_test() {
  let t = tree.unfold(8, shrink_int_toward_zero)
  let direct =
    t.shrinks
    |> to_list()
    |> list.map(fn(child) { child.value })
  should.equal(direct, [4])
}

pub fn map_preserves_shrink_structure_test() {
  let t = tree.unfold(4, shrink_int_toward_zero)
  let mapped = tree.map(t, fn(n) { n + 100 })
  should.equal(mapped.value, 104)
  let direct =
    mapped.shrinks
    |> to_list()
    |> list.map(fn(child) { child.value })
  should.equal(direct, [102])
}

pub fn zip_shrinks_each_component_independently_test() {
  let t1 = tree.unfold(2, shrink_int_toward_zero)
  let t2 = tree.singleton("x")
  let zipped = tree.zip(t1, t2)
  should.equal(zipped.value, #(2, "x"))
  let direct =
    zipped.shrinks
    |> to_list()
    |> list.map(fn(child) { child.value })
  // left has one direct shrink (1), right has none — only the left
  // shrink should appear, with the right component held fixed.
  should.equal(direct, [#(1, "x")])
}

pub fn bind_chains_inner_and_outer_shrinks_test() {
  let outer = tree.singleton(3)
  let bound = tree.bind(outer, fn(v) { tree.singleton(v * 10) })
  should.equal(bound.value, 30)
  should.equal(to_list(bound.shrinks), [])
}

pub fn filter_drops_failing_shrinks_test() {
  let t = tree.unfold(8, shrink_int_toward_zero)
  let positive_only = tree.filter(t, fn(n) { n > 0 })
  let values = all_values(positive_only)
  should.equal(values, [8, 4, 2, 1])
}

pub fn no_shrinks_is_empty_test() {
  should.equal(to_list(tree.no_shrinks()), [])
}

pub fn lazy_shrinks_keeps_the_given_order_test() {
  let t =
    tree.Tree(
      value: 5,
      shrinks: tree.lazy_shrinks(fn() { [tree.singleton(1), tree.singleton(3)] }),
    )
  should.equal(all_values(t), [5, 1, 3])
}

pub fn lazy_shrinks_lists_nothing_until_forced_test() {
  count_reset()
  let stream =
    tree.lazy_shrinks(fn() {
      count_bump()
      [1, 2, 3]
    })
  count_get() |> should.equal(0)
  to_list(stream) |> should.equal([1, 2, 3])
  count_get() |> should.equal(1)
}

@external(erlang, "metamon_env_test_ffi", "count_reset")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_reset")
fn count_reset() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_bump")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_bump")
fn count_bump() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_get")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_get")
fn count_get() -> Int
