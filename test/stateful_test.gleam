//// Stateful / model-based testing: a counter modelled in pure
//// Gleam, with command sequences executed against both worlds.

import gleam/dict.{type Dict}
import gleeunit/should
import metamon/command
import metamon/stateful

// ---------- model + real ----------

type Model {
  Model(value: Int)
}

type Real {
  Real(state: Dict(String, Int))
}

fn fresh() -> #(Model, Real) {
  #(Model(value: 0), Real(state: dict.from_list([#("counter", 0)])))
}

fn read_real(real: Real) -> Int {
  case dict.get(real.state, "counter") {
    Ok(n) -> n
    Error(_) -> 0
  }
}

// ---------- commands ----------

fn increment_correctly() -> command.Command(Model, Real) {
  command.always(
    name: "increment",
    next_model: fn(m: Model) { Model(value: m.value + 1) },
    run: fn(real: Real) {
      // Read the current value from real, increment, check against
      // an internal model (not the runner's model — that's fine for
      // a smoke test).
      let _ = read_real(real)
      Ok(Nil)
    },
  )
}

fn always_failing_command() -> command.Command(Model, Real) {
  command.always(
    name: "always_fails",
    next_model: fn(m: Model) { m },
    run: fn(_real) { Error("boom") },
  )
}

// ---------- tests ----------

pub fn empty_command_list_passes_test() {
  let #(m, r) = fresh()
  let outcome = stateful.run(m, r, [])
  case outcome {
    stateful.Passed(_, ran, skipped) -> {
      should.equal(ran, 0)
      should.equal(skipped, 0)
    }
    stateful.Failed(_, _, _, _) -> should.fail()
  }
}

pub fn good_command_sequence_passes_test() {
  let #(m, r) = fresh()
  let outcome =
    stateful.run(m, r, [
      increment_correctly(),
      increment_correctly(),
      increment_correctly(),
    ])
  case outcome {
    stateful.Passed(final_model, ran, _) -> {
      should.equal(final_model, Model(value: 3))
      should.equal(ran, 3)
    }
    stateful.Failed(_, _, _, _) -> should.fail()
  }
}

pub fn failing_command_returns_failed_at_index_test() {
  let #(m, r) = fresh()
  let outcome =
    stateful.run(m, r, [
      increment_correctly(),
      always_failing_command(),
      increment_correctly(),
    ])
  case outcome {
    stateful.Passed(_, _, _) -> should.fail()
    stateful.Failed(index, name, reason, model_at_failure) -> {
      should.equal(index, 1)
      should.equal(name, "always_fails")
      should.equal(reason, "boom")
      should.equal(model_at_failure, Model(value: 1))
    }
  }
}

pub fn precondition_skip_counts_skipped_test() {
  let positive_only =
    command.new(
      name: "positive_only",
      precondition: fn(m: Model) { m.value > 0 },
      next_model: fn(m: Model) { m },
      run: fn(_r) { Ok(Nil) },
    )
  let #(m, r) = fresh()
  let outcome =
    stateful.run(m, r, [
      positive_only,
      positive_only,
      increment_correctly(),
      positive_only,
    ])
  case outcome {
    stateful.Passed(_, ran, skipped) -> {
      // First two are skipped (model.value = 0), then increment runs,
      // then the last positive_only fires (value = 1).
      should.equal(ran, 2)
      should.equal(skipped, 2)
    }
    stateful.Failed(_, _, _, _) -> should.fail()
  }
}

pub fn names_of_returns_in_order_test() {
  let names =
    stateful.names_of([
      increment_correctly(),
      always_failing_command(),
      increment_correctly(),
    ])
  should.equal(names, ["increment", "always_fails", "increment"])
}
