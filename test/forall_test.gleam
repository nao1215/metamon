import gleam/option.{Some}
import gleeunit/should
import metamon
import metamon/generator

pub fn forall_passes_when_property_always_true_test() {
  metamon.forall(generator.int(generator.range(0, 100)), fn(n) {
    assert n >= 0 && n <= 100
  })
}

pub fn forall_passes_for_simple_int_property_test() {
  metamon.forall(generator.int(generator.range(-1000, 1000)), fn(n) {
    assert n + 0 == n
  })
}

pub fn forall_passes_with_explicit_seed_test() {
  let c = metamon.Config(..metamon.default_config(), seed: Some(7), runs: 30)
  metamon.forall_with(c, generator.int(generator.range(0, 50)), fn(n) {
    assert n >= 0
  })
  should.equal(1, 1)
}

pub fn forall_passes_for_list_length_invariant_test() {
  metamon.forall(
    generator.list_of(
      generator.int(generator.range(0, 9)),
      generator.range(0, 5),
    ),
    fn(items) {
      // length must be ≥ 0 (trivial, but exercises list generation)
      assert length_ge_zero(items)
    },
  )
}

fn length_ge_zero(items: List(Int)) -> Bool {
  case items {
    [] -> True
    [_, ..rest] -> length_ge_zero(rest)
  }
}
