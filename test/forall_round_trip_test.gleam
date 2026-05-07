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

pub fn forall_round_trip_partial_skips_rejected_inputs_test() {
  // Encoder rejects every odd input — the property must still pass
  // for the even inputs and skip the odd ones (treating them as out
  // of scope, not as failures).
  metamon.forall_round_trip_partial(
    gen: generator.int(range.constant(-50, 50)),
    name: "even_only_round_trip",
    encode: fn(n) {
      case n % 2 == 0 {
        True -> Ok(int.to_string(n))
        False -> Error(Nil)
      }
    },
    decode: fn(s) { int.parse(s) },
  )
}

pub fn forall_round_trip_partial_succeeds_when_encoder_total_test() {
  // When the encoder never returns Error, behaviour matches
  // forall_round_trip exactly.
  metamon.forall_round_trip_partial(
    gen: generator.int(range.constant(-100, 100)),
    name: "always_total",
    encode: fn(n) { Ok(int.to_string(n)) },
    decode: fn(s) { int.parse(s) },
  )
}

pub fn forall_round_trip_partial_with_explicit_config_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(7))
    |> metamon.with_runs_or_panic(30)
  metamon.forall_round_trip_partial_with(
    cfg: cfg,
    gen: generator.int(range.constant(0, 200)),
    name: "non_negative_only",
    encode: fn(n) {
      case n >= 0 {
        True -> Ok(int.to_string(n))
        False -> Error(Nil)
      }
    },
    decode: fn(s) { int.parse(s) },
  )
}
