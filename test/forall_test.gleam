import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range

pub fn forall_passes_when_property_always_true_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(n) {
    n >= 0 && n <= 100
  })
}

pub fn forall_passes_for_simple_int_property_test() {
  metamon.forall(generator.int(range.constant(-1000, 1000)), fn(n) {
    n + 0 == n
  })
}

pub fn forall_passes_with_explicit_seed_test() {
  let c =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(7))
    |> metamon.with_runs_or_panic(30)
  metamon.forall_with(c, generator.int(range.constant(0, 50)), fn(n) { n >= 0 })
  should.equal(1, 1)
}

pub fn forall_passes_for_list_length_invariant_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    fn(items) {
      // length must be ≥ 0 (trivial, but exercises list generation)
      length_ge_zero(items)
    },
  )
}

fn length_ge_zero(items: List(Int)) -> Bool {
  case items {
    [] -> True
    [_, ..rest] -> length_ge_zero(rest)
  }
}
