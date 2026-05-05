//// Edge-value propagation rules for the built-in generators and
//// combinators. The implementation guarantees described in spec § 4.4
//// are exercised here.
////
//// Inspired by:
////   - dubzzz/fast-check — biased generation tests under
////     `packages/fast-check/test/unit/arbitrary/` (MIT)
////   - mooreryan/gleam_qcheck — `gen_int_test`, `gen_list_test`,
////     `gen_option_test` (Apache-2.0 / MIT)
////
//// All test bodies are independent re-implementations against the
//// metamon API. No upstream source code has been copied.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import metamon/generator
import metamon/generator/range

// ---------- propagation through map / filter / one_of ----------

pub fn map_propagates_edges_under_function_test() {
  // map(g, f).edges == g.edges |> map(f)
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3])
  let mapped = generator.map(g, fn(n) { n * 10 })
  let edges = generator.edges_of(mapped)
  should.be_true(list.contains(edges, 0))
  should.be_true(list.contains(edges, 10))
  should.be_true(list.contains(edges, 20))
  should.be_true(list.contains(edges, 30))
}

pub fn filter_drops_edges_failing_predicate_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3, 4, 5])
    |> generator.filter(fn(n) { n > 2 })
  let edges = generator.edges_of(g)
  list.each(edges, fn(e) { should.be_true(e > 2) })
  // 0, 1, 2 must not appear; 3, 4, 5 must appear.
  should.be_false(list.contains(edges, 0))
  should.be_true(list.contains(edges, 3))
  should.be_true(list.contains(edges, 5))
}

pub fn one_of_concatenates_branch_edges_test() {
  let g =
    generator.one_of([
      generator.return(0) |> generator.with_examples([1]),
      generator.return(0) |> generator.with_examples([2]),
    ])
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 1))
  should.be_true(list.contains(edges, 2))
}

// ---------- standard generators carry useful edges ----------

pub fn int_with_negative_range_edges_include_zero_test() {
  let g = generator.int(range.constant(-100, 100))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 0))
  should.be_true(list.contains(edges, 1))
  should.be_true(list.contains(edges, -1))
}

pub fn int_with_positive_range_edges_avoid_unreachable_test() {
  // For a range entirely above zero, -1 must not be in edges
  // (otherwise the runner would attempt impossible inputs).
  let g = generator.int(range.constant(10, 50))
  let edges = generator.edges_of(g)
  list.each(edges, fn(e) { should.be_true(e >= 10 && e <= 50) })
  should.be_false(list.contains(edges, -1))
}

pub fn list_of_edges_include_empty_and_singleton_test() {
  let g = generator.list_of(generator.return(7), range.constant(0, 4))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, []))
  should.be_true(list.contains(edges, [7]))
}

pub fn option_of_edges_include_none_and_a_some_test() {
  let g = generator.option_of(generator.return(99))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, None))
  should.be_true(list.contains(edges, Some(99)))
}

pub fn result_of_edges_include_ok_and_error_test() {
  let g = generator.result_of(generator.return("yes"), generator.return("no"))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, Ok("yes")))
  should.be_true(list.contains(edges, Error("no")))
}

// ---------- with_examples / add_edges / no_edges ----------

pub fn with_examples_appends_edges_in_order_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3])
  let edges = generator.edges_of(g)
  // The original return-edge `0` comes first, then the examples in
  // user-supplied order.
  case edges {
    [first, ..] -> should.equal(first, 0)
    [] -> should.fail()
  }
  should.be_true(list.contains(edges, 1))
  should.be_true(list.contains(edges, 2))
  should.be_true(list.contains(edges, 3))
}

pub fn no_edges_drops_examples_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3])
    |> generator.no_edges()
  should.equal(generator.edges_of(g), [])
}

pub fn add_edges_is_equivalent_to_with_examples_test() {
  let a =
    generator.return(0)
    |> generator.with_examples([5])
  let b =
    generator.return(0)
    |> generator.add_edges([5])
  should.equal(generator.edges_of(a), generator.edges_of(b))
}

// ---------- cartesian cap ----------

pub fn map2_caps_cartesian_edge_blow_up_test() {
  // Two generators with 5 edges each would yield 25 in the worst
  // case. The implementation caps at `default_max_edges = 16`.
  let many =
    generator.return(0)
    |> generator.with_examples([1, 2, 3, 4])
  let g = generator.map2(many, many, fn(a, b) { #(a, b) })
  let edges = generator.edges_of(g)
  should.be_true(count_pairs(edges) <= 16)
}

fn count_pairs(items: List(#(Int, Int))) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + count_pairs(rest)
  }
}
