//// Tests that exercise the failure path: forall / forall_morph
//// should panic with a structured failure report when a property
//// does not hold. We catch the panic via gleeunit's per-test process
//// isolation and inspect the panic reason.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import test_helpers

pub type CapturedPanic {
  Reason(message: String)
  NoPanic
}

fn capture(thunk: fn() -> Nil) -> CapturedPanic {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  case panicked {
    True -> Reason(message: message)
    False -> NoPanic
  }
}

pub fn forall_panics_on_violation_test() {
  let outcome =
    capture(fn() {
      metamon.forall(
        generator.int(generator.range(0, 100)),
        // false for everything ≥ 0, which is everything → instant fail
        fn(_n) { test_helpers.fail() },
      )
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(text, "× property failed"))
      should.be_true(string.contains(text, "config seed:"))
      should.be_true(string.contains(text, "reproduce (paste into a test):"))
    }
    NoPanic -> should.fail()
  }
}

pub fn forall_morph_panics_with_named_relation_test() {
  // Build an MR that always fails by claiming the input is invariant
  // under "increment" (which it obviously is not).
  let increment = metamon.Transform("+1", fn(n) { n + 1 })
  let bad_mr =
    metamon.Morph(
      name: "false_invariant_under_increment",
      transform: increment,
      relation: metamon.equal(),
    )
  let outcome =
    capture(fn() {
      metamon.forall_morph(
        generator.int(generator.range(1, 10)),
        [bad_mr],
        fn(n) { n },
      )
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(
        text,
        "× metamorphic relation `false_invariant_under_increment` failed",
      ))
      should.be_true(string.contains(text, "transform:   `+1`"))
      should.be_true(string.contains(text, "relation:    `equal`"))
    }
    NoPanic -> should.fail()
  }
}

pub fn assert_morph_panics_on_violation_test() {
  let increment = metamon.Transform("+1", fn(n) { n + 1 })
  let bad_mr =
    metamon.Morph(
      name: "fails_for_assert_morph",
      transform: increment,
      relation: metamon.equal(),
    )
  let outcome = capture(fn() { metamon.assert_morph(5, bad_mr, fn(n) { n }) })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(text, "fails_for_assert_morph"))
    }
    NoPanic -> should.fail()
  }
}

pub fn forall_round_trip_panics_on_decode_error_test() {
  let outcome =
    capture(fn() {
      metamon.forall_round_trip(
        generator: generator.int(generator.range(0, 100)),
        name: "broken",
        encode: int.to_string,
        decode: fn(_value) { Error(Nil) },
      )
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(text, "round_trip[broken]"))
      should.be_true(string.contains(text, "× property failed"))
    }
    NoPanic -> should.fail()
  }
}

pub fn forall_morph_panics_on_empty_morph_list_test() {
  let outcome =
    capture(fn() {
      metamon.forall_morph(generator.int(generator.range(0, 100)), [], fn(n) {
        n
      })
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(text, "metamon.forall_morph"))
      should.be_true(string.contains(text, "empty morph list"))
      should.be_true(string.contains(text, "vacuous test"))
    }
    NoPanic -> should.fail()
  }
}

pub fn config_seed_zero_renders_with_the_configured_seed_test() {
  // Pin seed(0) so the runner's normalisation maps it to 0xDEADBEEF.
  // The failure header should annotate the canonical state with the
  // seed the user wrote in the Config.
  let cfg = metamon.Config(..metamon.default_config(), seed: Some(0))
  let outcome =
    capture(fn() {
      metamon.forall_with(cfg, generator.int(generator.range(0, 100)), fn(_n) {
        test_helpers.fail()
      })
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(text, "config seed:"))
      should.be_true(string.contains(
        text,
        "Config(..default_config(), seed: Some(0))",
      ))
    }
    NoPanic -> should.fail()
  }
}

pub fn morph_reproduce_line_uses_assert_morph_test() {
  let reverse = metamon.Transform(name: "reverse", apply: list.reverse)
  let outcome =
    capture(fn() {
      metamon.forall_morph(
        generator.list_of(
          generator.int(generator.range(0, 9)),
          generator.range(2, 5),
        ),
        [metamon.invariant_under(name: "head", under: reverse)],
        list.first,
      )
    })
  case outcome {
    Reason(text) -> {
      should.be_true(string.contains(
        text,
        "metamon.assert_morph(input, morph, function)",
      ))
      should.be_false(string.contains(text, " MR "))
    }
    NoPanic -> should.fail()
  }
}

pub fn runs_smaller_than_the_edge_count_limits_the_inputs_test() {
  // One run per multiplier step; the 16 edge values must not add more.
  count_reset()
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 1),
    generator.int(generator.range(0, 9)) |> generator.no_edges,
    fn(_) { count_bump() },
  )
  let plain = count_get()
  count_reset()
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 1),
    generator.int(generator.range(0, 1000))
      |> generator.with_examples(test_helpers.integers_from(0, 16)),
    fn(_) { count_bump() },
  )
  should.equal(count_get(), plain)
}

@external(erlang, "metamon_env_test_ffi", "count_reset")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_reset")
fn count_reset() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_bump")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_bump")
fn count_bump() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_get")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_get")
fn count_get() -> Int
