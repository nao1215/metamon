import gleam/int
import metamon
import metamon/generator
import metamon/generator/range

pub fn forall_round_trip_int_to_string_test() {
  metamon.forall_round_trip(
    gen: generator.int(range.constant(-1000, 1000)),
    name: "int_to_string",
    encode: int.to_string,
    decode: int.parse,
  )
}

pub fn forall_round_trip_identity_test() {
  metamon.forall_round_trip(
    gen: generator.int(range.constant(0, 100)),
    name: "identity",
    encode: fn(value) { value },
    decode: fn(value) { Ok(value) },
  )
}

pub fn forall_round_trip_with_explicit_config_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(42))
    |> metamon.with_runs_or_panic(30)
  metamon.forall_round_trip_with(
    cfg: cfg,
    gen: generator.int(range.constant(-100, 100)),
    name: "int_to_string_seeded",
    encode: int.to_string,
    decode: int.parse,
  )
}
