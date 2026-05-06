import metamon
import metamon/generator
import metamon/generator/range

pub fn forall_observable_passes_when_predicate_holds_test() {
  metamon.forall_observable(generator.int(range.constant(0, 100)), fn(input) {
    let doubled = input * 2
    #(doubled, doubled >= input)
  })
}

pub fn forall_observable_with_explicit_config_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(11))
    |> metamon.with_runs_or_panic(20)
  metamon.forall_observable_with(
    cfg,
    generator.int(range.constant(-50, 50)),
    fn(input) { #(input + 1, True) },
  )
}
