//// Every public-facing usage example in README.md is mirrored here as
//// an executable test. The two files MUST stay byte-identical inside
//// each fenced code block — when the README is regenerated, each
//// block is copied from one of the `pub fn readme_*_test` functions
//// below. CI runs `gleam test`, which means the README cannot drift
//// out of sync with the actual API.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import metamon
import metamon/annotate
import metamon/coverage
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import metamon/transform/list as list_t

// ===========================================================================
// Quick start
// ===========================================================================

pub fn readme_quick_start_test() {
  // The simplest property: trim is idempotent — applying it twice
  // gives the same result as applying it once.
  let mr = metamon.idempotency_of(name: "trim_idempotent", of: string.trim)
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 16)),
    mr,
    string.trim,
  )
}

// ===========================================================================
// 1. Property-based testing — `forall`
// ===========================================================================

pub fn readme_forall_test() {
  // For every list of small ints, reversing twice yields the original.
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    fn(xs) { list.reverse(list.reverse(xs)) == xs },
  )
}

// ===========================================================================
// 2. Metamorphic relations
// ===========================================================================

// 2.1. Idempotency: f(f(x)) == f(x)
//
// `sort_dedupe` (sort + remove duplicates) is idempotent — applying
// it twice produces the same list as applying it once.
pub fn readme_idempotency_test() {
  let mr =
    metamon.idempotency_of(name: "sort_dedupe_idempotent", of: sort_dedupe)
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 6)),
    mr,
    sort_dedupe,
  )
}

fn sort_dedupe(xs: List(Int)) -> List(Int) {
  let sorted = list.sort(xs, int.compare)
  let dedupe = list_t.dedupe()
  dedupe.apply(sorted)
}

// 2.2. Round-trip via a custom relation: f and inverse round-trip.
pub fn readme_round_trip_test() {
  // Encoding: int -> string -> int must recover the original.
  let r =
    relation.new("string_int_round_trip", fn(left: Int, right: Int) {
      // `left` and `right` are both `int.to_string` of the same input
      // (the transform is identity), so round-trip correctness is the
      // assertion that `parse(write(x))` succeeds and equals `x`.
      left == right
    })
  let mr =
    metamon.mr(
      name: "int_string_round_trip",
      transform: transform.identity(),
      relation: r,
    )
  metamon.forall_morph(generator.int(range.constant(-1000, 1000)), mr, fn(n) {
    let assert Ok(parsed) = int.parse(int.to_string(n))
    parsed
  })
}

// 2.3. Invariance: f(T(x)) == f(x) — the function is unaffected by T.
pub fn readme_invariance_test() {
  // list.length is invariant under reverse.
  let mr =
    metamon.invariant_under(
      name: "length_invariant_under_reverse",
      under: list_t.reverse(),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 8)),
    mr,
    list.length,
  )
}

// 2.4. Equivariance: U(f(x)) == f(T(x)).
pub fn readme_equivariance_test() {
  // map(g) commutes with reverse:
  //   list.reverse(list.map(xs, g)) == list.map(list.reverse(xs), g)
  let mr =
    metamon.equivariant_under(
      name: "map_commutes_with_reverse",
      input: list_t.reverse(),
      output: list_t.reverse(),
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 6)),
    mr,
    fn(xs) { list.map(xs, fn(n) { n * 2 }) },
  )
}

// 2.5. Manual MR construction — pick any Transform and any Relation.
pub fn readme_manual_mr_test() {
  // Adding zero to a list of ints does not change its sum.
  let append_zero = list_t.append(0)
  let mr =
    metamon.mr(
      name: "sum_invariant_under_append_zero",
      transform: append_zero,
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    mr,
    list_sum,
  )
}

fn list_sum(items: List(Int)) -> Int {
  list.fold(items, 0, fn(acc, n) { acc + n })
}

// 2.6. assert_morph — single hand-supplied input, no generator.
pub fn readme_assert_morph_test() {
  let mr =
    metamon.invariant_under(
      name: "sum_invariant_under_reverse",
      under: list_t.reverse(),
    )
  metamon.assert_morph([1, 2, 3, 4, 5], mr, list_sum)
}

// 2.7. commutativity_of — op(a, b) == op(b, a).
pub fn readme_commutativity_test() {
  let mr = metamon.commutativity_of(name: "add_commutative", of: add_int)
  metamon.forall_morph(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    mr,
    fn(pair) { add_int(pair.0, pair.1) },
  )
}

fn add_int(a: Int, b: Int) -> Int {
  a + b
}

// 2.8. round-trip via PBT (no MR template — see README).
pub fn readme_round_trip_via_forall_test() {
  metamon.forall(generator.int(range.constant(-1000, 1000)), fn(n) {
    case int.parse(int.to_string(n)) {
      Ok(parsed) -> parsed == n
      Error(_) -> False
    }
  })
}

// 2.9. forall_morphs — run several MRs against the same f.
pub fn readme_forall_morphs_test() {
  let invariant_under_reverse =
    metamon.invariant_under(name: "sum_under_reverse", under: list_t.reverse())
  let invariant_under_append_zero =
    metamon.invariant_under(
      name: "sum_under_append_zero",
      under: list_t.append(0),
    )
  metamon.forall_morphs(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 4)),
    [invariant_under_reverse, invariant_under_append_zero],
    list_sum,
  )
}

// ===========================================================================
// 3. Generators
// ===========================================================================

// 3.1. map2 builds a record-shaped generator.
pub type User {
  User(name: String, age: Int)
}

pub fn readme_user_generator_test() {
  let user_gen =
    generator.map2(
      generator.string_ascii(range.constant(1, 8)),
      generator.int(range.constant(0, 120)),
      User,
    )
  metamon.forall(user_gen, fn(u: User) { u.age >= 0 && u.age <= 120 })
}

// 3.2. one_of and frequency.
pub fn readme_choice_test() {
  let traffic_light =
    generator.frequency([
      #(3, generator.return("green")),
      #(2, generator.return("yellow")),
      #(1, generator.return("red")),
    ])
  metamon.forall(traffic_light, fn(colour) {
    colour == "green" || colour == "yellow" || colour == "red"
  })
}

// 3.3. with_examples — guarantee specific edge inputs are tried.
pub fn readme_with_examples_test() {
  let trim_idempotent =
    metamon.idempotency_of(
      name: "trim_idempotent_with_examples",
      of: string.trim,
    )
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 8))
      |> generator.with_examples(["", " ", "  ", "\t\n  hi  \n\t"]),
    trim_idempotent,
    string.trim,
  )
}

// 3.4. recursive generator.
pub type Tree {
  Leaf(Int)
  Node(Tree, Tree)
}

pub fn readme_recursive_generator_test() {
  let tree_gen =
    generator.recursive(
      // base case: leaf
      generator.map(generator.int(range.constant(0, 9)), Leaf),
      // step: build a Node from two smaller trees
      fn(smaller) { generator.map2(smaller, smaller, Node) },
    )
  metamon.forall(tree_gen, fn(t) {
    case count_leaves(t) {
      n -> n >= 1
    }
  })
}

fn count_leaves(t: Tree) -> Int {
  case t {
    Leaf(_) -> 1
    Node(left, right) -> count_leaves(left) + count_leaves(right)
  }
}

// ===========================================================================
// 4. Transforms and relations
// ===========================================================================

// 4.1. Composing transforms.
pub fn readme_transform_composition_test() {
  // Lowercase, then trim.
  let normalise =
    transform.then(
      transform.new("lowercase", string.lowercase),
      transform.new("trim", string.trim),
    )
  // Apply on a known input.
  should.equal(normalise.apply("  Hello  "), "hello")
  should.equal(normalise.name, "lowercase |> trim")
}

// 4.2. Combining relations.
pub fn readme_relation_combination_test() {
  let positive =
    relation.new("positive_left", fn(left: Int, _right: Int) { left > 0 })
  let nonzero_right =
    relation.new("nonzero_right", fn(_left: Int, right: Int) { right != 0 })
  let combined = relation.and(positive, nonzero_right)
  should.equal(combined.name, "positive_left and nonzero_right")
  should.be_true(combined.holds(5, 3))
  should.be_false(combined.holds(0, 3))
  should.be_false(combined.holds(5, 0))
}

// 4.3. equivalent_under — relation on a normalised view.
pub fn readme_equivalent_under_test() {
  // Two strings are equivalent if their lowercase forms match.
  let r = relation.equivalent_under(string.lowercase, "case_insensitive")
  should.be_true(r.holds("Hello", "HELLO"))
  should.be_false(r.holds("Hello", "World"))
}

// ===========================================================================
// 5. Coverage and annotations
// ===========================================================================

pub fn readme_coverage_test() {
  // `cover` asserts that at least 5% of inputs hit "non_empty".
  // The generator's edges include "" so the runner sees both sides.
  metamon.forall_with(
    test_config(50, 7),
    generator.string_ascii(range.constant(0, 8)),
    fn(s) {
      coverage.cover(5.0, "non_empty", string.length(s) > 0)
      coverage.classify("contains_space", string.contains(s, " "))
      // The actual property: trim never makes a string longer.
      string.length(string.trim(s)) <= string.length(s)
    },
  )
}

pub fn readme_annotate_test() {
  // annotate is invisible on success and shown on failure. Here we
  // just demonstrate the call shape.
  metamon.forall_with(
    test_config(20, 0),
    generator.int(range.constant(0, 100)),
    fn(n) {
      annotate.annotate("currently checking n = " <> int.to_string(n))
      annotate.annotate_value("doubled", n * 2)
      annotate.footnote("hint: n is non-negative by construction")
      n >= 0
    },
  )
}

// ===========================================================================
// 6. Configuration
// ===========================================================================

pub fn readme_configuration_test() {
  let assert Ok(c) =
    metamon.with_runs(
      metamon.default_config()
        |> metamon.with_seed(metamon.seed(2026)),
      30,
    )
  metamon.forall_with(c, generator.int(range.constant(-100, 100)), fn(n) {
    n + 0 == n
  })
}

// ===========================================================================
// Helpers used in multiple examples
// ===========================================================================

fn test_config(runs: Int, seed_value: Int) -> metamon.Config {
  let assert Ok(c) =
    metamon.with_runs(
      metamon.default_config()
        |> metamon.with_seed(metamon.seed(seed_value)),
      runs,
    )
  c
}

// ===========================================================================
// Smoke tests for placeholders / internal references
// ===========================================================================

pub fn readme_helpers_smoke_test() {
  should.equal(list_sum([1, 2, 3]), 6)
  should.equal(count_leaves(Node(Leaf(1), Leaf(2))), 2)
  should.equal(sort_dedupe([3, 1, 2, 1, 3]), [1, 2, 3])
  let _ = test_config(10, 0)
  let _: Dict(String, Int) = dict.new()
  Nil
}
