import gleam/list
import gleeunit/should
import metamon/generator/tree

fn shrink_int_toward_zero(value: Int) -> List(Int) {
  case value {
    0 -> []
    _ -> [value / 2]
  }
}

pub fn singleton_has_no_shrinks_test() {
  let t = tree.singleton(42)
  should.equal(t.value, 42)
  should.equal(tree.shrinks_to_list(t.shrinks), [])
}

pub fn unfold_uses_expand_recursively_test() {
  let t = tree.unfold(8, shrink_int_toward_zero)
  let direct =
    t.shrinks
    |> tree.shrinks_to_list()
    |> list.map(fn(child) { child.value })
  should.equal(direct, [4])
}

pub fn map_preserves_shrink_structure_test() {
  let t = tree.unfold(4, shrink_int_toward_zero)
  let mapped = tree.map(t, fn(n) { n + 100 })
  should.equal(mapped.value, 104)
  let direct =
    mapped.shrinks
    |> tree.shrinks_to_list()
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
    |> tree.shrinks_to_list()
    |> list.map(fn(child) { child.value })
  // left has one direct shrink (1), right has none — only the left
  // shrink should appear, with the right component held fixed.
  should.equal(direct, [#(1, "x")])
}

pub fn bind_chains_inner_and_outer_shrinks_test() {
  let outer = tree.singleton(3)
  let bound = tree.bind(outer, fn(v) { tree.singleton(v * 10) })
  should.equal(bound.value, 30)
  should.equal(tree.shrinks_to_list(bound.shrinks), [])
}

pub fn filter_drops_failing_shrinks_test() {
  let t = tree.unfold(8, shrink_int_toward_zero)
  let positive_only = tree.filter(t, fn(n) { n > 0 })
  let outline = tree.outline(positive_only, 4, 8)
  list.each(outline, fn(value) { should.be_true(value > 0) })
}

pub fn shrinks_take_returns_first_n_elements_test() {
  let s = tree.shrinks_from_list([10, 20, 30, 40, 50])
  should.equal(tree.shrinks_take(s, 3), [10, 20, 30])
}

pub fn shrinks_take_clamps_at_stream_end_test() {
  let s = tree.shrinks_from_list([10, 20])
  should.equal(tree.shrinks_take(s, 5), [10, 20])
}

pub fn shrinks_take_handles_empty_test() {
  should.equal(tree.shrinks_take(tree.no_shrinks(), 5), [])
}
