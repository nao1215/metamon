//// Functor / monad / applicative laws for `metamon/generator`.
////
//// Inspired by:
////   - mooreryan/gleam_qcheck — `test/qcheck/gen_algebra_test.gleam`
////     (Apache-2.0 / MIT)
////   - hedgehogqa/haskell-hedgehog — `Hedgehog.Gen` law sketches
////     (BSD-3-Clause)
////
//// Every test body below is an independent re-implementation against
//// the metamon API. No upstream source code has been copied.

import gleeunit/should
import metamon/generator
import metamon/generator/range
import metamon/generator/seed

// ---------- functor laws ----------

pub fn map_identity_law_test() {
  // map(g, id) and g must produce identical values for the same seed.
  let g = generator.int(range.constant(0, 100))
  let mapped = generator.map(g, fn(x) { x })
  let s = seed.seed(7)
  should.equal(
    generator.generate(g, s, 50).value,
    generator.generate(mapped, s, 50).value,
  )
}

pub fn map_composition_law_test() {
  // map(g, h) ∘ map(_, f) ≡ map(g, h ∘ f) for any deterministic f, h.
  let g = generator.int(range.constant(0, 50))
  let f = fn(x: Int) { x * 2 }
  let h = fn(x: Int) { x + 1 }
  let lhs = generator.map(generator.map(g, f), h)
  let rhs = generator.map(g, fn(x) { h(f(x)) })
  let s = seed.seed(13)
  should.equal(
    generator.generate(lhs, s, 50).value,
    generator.generate(rhs, s, 50).value,
  )
}

// ---------- applicative law: map2 with identity == zip ----------

pub fn map2_with_pair_constructor_equals_tuple2_test() {
  let g1 = generator.int(range.constant(0, 9))
  let g2 = generator.int(range.constant(100, 199))
  let by_map2 = generator.map2(g1, g2, fn(a, b) { #(a, b) })
  let by_tuple = generator.tuple2(g1, g2)
  let s = seed.seed(41)
  should.equal(
    generator.generate(by_map2, s, 99).value,
    generator.generate(by_tuple, s, 99).value,
  )
}

// ---------- monad-style law: return + bind = direct map ----------

pub fn bind_left_identity_for_pure_test() {
  // bind(return(x), k) ≡ k(x) when k uses no randomness inside.
  let s = seed.seed(0)
  let lhs =
    generator.bind(generator.return(7), fn(x) { generator.return(x + 1) })
  let rhs = generator.return(8)
  should.equal(
    generator.generate(lhs, s, 0).value,
    generator.generate(rhs, s, 0).value,
  )
}

// ---------- determinism ----------

pub fn same_seed_yields_same_value_test() {
  // Determinism is the foundation of every other law: same generator,
  // same seed, same size → bit-identical output every time.
  let g =
    generator.list_of(
      generator.int(range.constant(0, 99)),
      range.constant(0, 5),
    )
  let s = seed.seed(2026)
  should.equal(
    generator.generate(g, s, 50).value,
    generator.generate(g, s, 50).value,
  )
}

// ---------- map3..6 sanity ----------

pub fn map3_distributes_over_tuple3_test() {
  let g1 = generator.int(range.constant(0, 1))
  let g2 = generator.int(range.constant(2, 3))
  let g3 = generator.int(range.constant(4, 5))
  let by_map3 = generator.map3(g1, g2, g3, fn(a, b, c) { #(a, b, c) })
  let by_tuple = generator.tuple3(g1, g2, g3)
  let s = seed.seed(7)
  should.equal(
    generator.generate(by_map3, s, 99).value,
    generator.generate(by_tuple, s, 99).value,
  )
}
