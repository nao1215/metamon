//// `Config` is a plain record. The runners check it when they start and
//// panic with a message naming the invalid field.

import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

fn run(config: metamon.Config) -> #(Bool, String) {
  capture_panic(fn() {
    metamon.forall_with(config, generator.int(range.constant(0, 9)), fn(_) {
      True
    })
  })
}

fn assert_rejected(config: metamon.Config, field: String) -> Nil {
  let #(panicked, message) = run(config)
  should.be_true(panicked)
  should.be_true(string.contains(message, "Config." <> field))
}

fn assert_accepted(config: metamon.Config) -> Nil {
  let #(panicked, _) = run(config)
  should.be_false(panicked)
}

fn default() -> metamon.Config {
  metamon.default_config()
}

pub fn defaults_test() {
  should.equal(
    metamon.default_config(),
    metamon.Config(
      runs: 100,
      seed: None,
      max_size: 99,
      shrink_limit: 1024,
      max_edges: 16,
      regression_file: None,
      output: metamon.Text,
    ),
  )
}

pub fn runs_zero_or_negative_is_rejected_test() {
  assert_rejected(metamon.Config(..default(), runs: 0), "runs")
  assert_rejected(metamon.Config(..default(), runs: -1), "runs")
}

pub fn max_size_zero_or_negative_is_rejected_test() {
  assert_rejected(metamon.Config(..default(), max_size: 0), "max_size")
  assert_rejected(metamon.Config(..default(), max_size: -1), "max_size")
}

pub fn shrink_limit_zero_or_negative_is_rejected_test() {
  assert_rejected(metamon.Config(..default(), shrink_limit: 0), "shrink_limit")
  assert_rejected(metamon.Config(..default(), shrink_limit: -1), "shrink_limit")
}

pub fn max_edges_zero_or_negative_is_rejected_test() {
  assert_rejected(metamon.Config(..default(), max_edges: 0), "max_edges")
  assert_rejected(metamon.Config(..default(), max_edges: -1), "max_edges")
}

pub fn empty_regression_file_is_rejected_test() {
  assert_rejected(
    metamon.Config(..default(), regression_file: Some("")),
    "regression_file",
  )
}

pub fn the_message_shows_the_rejected_value_test() {
  let #(_, message) = run(metamon.Config(..default(), runs: -3))
  should.be_true(string.contains(message, "got -3"))
}

pub fn one_is_the_smallest_valid_value_test() {
  assert_accepted(
    metamon.Config(
      ..default(),
      runs: 1,
      max_size: 1,
      shrink_limit: 1,
      max_edges: 1,
    ),
  )
}

pub fn very_large_values_are_accepted_test() {
  // Only values <= 0 are rejected; the runner does not cap the others.
  assert_accepted(
    metamon.Config(
      ..default(),
      runs: 1,
      max_size: 1_000_000_000,
      shrink_limit: 1_000_000_000,
      max_edges: 1_000_000_000,
    ),
  )
}

pub fn every_runner_checks_the_config_test() {
  let bad = metamon.Config(..default(), runs: 0)
  let ints = generator.int(range.constant(0, 9))
  let #(morph_panicked, morph_message) =
    capture_panic(fn() {
      metamon.forall_morph_with(
        bad,
        ints,
        metamon.idempotency_of(name: "id", of: fn(x) { x }),
        fn(x) { x },
      )
    })
  should.be_true(morph_panicked)
  should.be_true(string.contains(morph_message, "Config.runs"))
  let #(round_trip_panicked, round_trip_message) =
    capture_panic(fn() {
      metamon.forall_round_trip_with(
        cfg: bad,
        gen: ints,
        name: "identity",
        encode: fn(x) { x },
        decode: Ok,
      )
    })
  should.be_true(round_trip_panicked)
  should.be_true(string.contains(round_trip_message, "Config.runs"))
}
