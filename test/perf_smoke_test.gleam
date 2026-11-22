//// Performance smoke test. Drives `forall_morph` at 1000 runs against
//// a non-trivial generator and asserts the run completes inside a
//// generous wall-clock budget. The goal is not to benchmark — it is
//// to catch O(n²) regressions in shrink expansion or edge
//// propagation that would otherwise silently turn a 100 ms run into
//// a 30 s timeout in CI.

import gleam/list
import gleam/option.{Some}
import gleeunit/should
import metamon
import metamon/generator

pub fn forall_morph_thousand_runs_finishes_quickly_test() {
  let mr =
    metamon.invariant_under(
      name: "length_under_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  let c = metamon.Config(..metamon.default_config(), seed: Some(0), runs: 1000)
  let started = monotonic_microseconds()
  metamon.forall_morph_with(
    c,
    generator.list_of(
      generator.int(generator.range(0, 100)),
      generator.range(0, 16),
    ),
    [mr],
    list.length,
  )
  let elapsed_us = monotonic_microseconds() - started
  // Generous: 1000 runs of length-under-reverse should fit easily
  // inside 5 seconds even on a small CI runner. If it doesn't,
  // there's a real performance regression to look at.
  should.be_true(elapsed_us < 5_000_000)
}

pub fn deep_recursive_tree_generator_finishes_quickly_test() {
  // A recursive Tree generator with 1000 runs is the worst case for
  // shrink expansion. Same wall-clock budget.
  let started = monotonic_microseconds()
  let c = metamon.Config(..metamon.default_config(), seed: Some(0), runs: 300)
  metamon.forall_with(c, recursive_tree_gen(), fn(t) {
    assert count_leaves(t) >= 1
  })
  let elapsed_us = monotonic_microseconds() - started
  should.be_true(elapsed_us < 5_000_000)
}

type RecTree {
  Leaf(Int)
  Node(RecTree, RecTree)
}

fn recursive_tree_gen() -> generator.Generator(RecTree) {
  generator.recursive(
    generator.map(generator.int(generator.range(0, 9)), Leaf),
    fn(smaller) { generator.map2(smaller, smaller, Node) },
  )
}

fn count_leaves(tree: RecTree) -> Int {
  case tree {
    Leaf(_) -> 1
    Node(left, right) -> count_leaves(left) + count_leaves(right)
  }
}

@external(erlang, "metamon_ffi", "now_microseconds")
@external(javascript, "./metamon_ffi.mjs", "now_microseconds")
fn monotonic_microseconds() -> Int
