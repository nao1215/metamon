import gleam/int
import gleam/option.{Some}
import metamon
import metamon/generator

pub fn forall_round_trip_identity_test() {
  metamon.forall_round_trip(
    generator: generator.int(generator.range(0, 100)),
    name: "identity",
    encode: fn(value) { value },
    decode: fn(value) { Ok(value) },
  )
}

pub fn forall_round_trip_with_explicit_config_test() {
  let cfg = metamon.Config(..metamon.default_config(), seed: Some(42), runs: 30)
  metamon.forall_round_trip_with(
    config: cfg,
    generator: generator.int(generator.range(-100, 100)),
    name: "int_to_string_seeded",
    encode: int.to_string,
    decode: int.parse,
  )
}
