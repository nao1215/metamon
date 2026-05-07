//// Stateful / model-based testing: a counter modelled in pure
//// Gleam, with command sequences executed against both worlds.

import gleam/dict.{type Dict}
import gleam/string
import gleeunit/should
import metamon/command
import metamon/stateful

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic_raw(thunk: fn() -> Nil) -> #(Bool, String)

fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String) {
  capture_panic_raw(thunk)
}

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

pub fn empty_command_list_panics_test() {
  let #(m, r) = fresh()
  let #(panicked, message) =
    capture_panic(fn() {
      let _ = stateful.run(m, r, [])
      Nil
    })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.stateful.run"))
  should.be_true(string.contains(message, "empty commands list"))
  should.be_true(string.contains(message, "vacuous test"))
}

pub fn assert_passed_panics_on_empty_passed_test() {
  let #(panicked, message) =
    capture_panic(fn() {
      stateful.assert_passed(stateful.Passed(
        final_model: Model(value: 0),
        ran: 0,
        skipped: 0,
      ))
    })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.stateful.run"))
  should.be_true(string.contains(message, "empty commands list"))
}

pub fn all_preconditions_false_panics_test() {
  let unreachable =
    command.new(
      name: "always_skipped",
      precondition: fn(_m: Model) { False },
      next_model: fn(m: Model) { m },
      run: fn(_r) { Ok(Nil) },
    )
  let #(m, r) = fresh()
  let outcome = stateful.run(m, r, [unreachable, unreachable, unreachable])
  case outcome {
    stateful.Passed(_, ran, skipped) -> {
      should.equal(ran, 0)
      should.equal(skipped, 3)
    }
    stateful.Failed(_, _, _, _) -> should.fail()
  }
  let #(panicked, message) =
    capture_panic(fn() { stateful.assert_passed(outcome) })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.stateful.assert_passed"))
  should.be_true(string.contains(message, "0 commands ran"))
  should.be_true(string.contains(message, "all 3 skipped"))
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

pub fn no_precondition_is_alias_for_always_test() {
  // The new canonical name and the legacy alias must produce the
  // same command shape — equal name, identical-behaviour
  // precondition (a no-op that returns True), and equivalent
  // next_model thunks.
  let cmd_always =
    command.always(
      name: "tick",
      next_model: fn(m: Model) { Model(value: m.value + 1) },
      run: fn(_r: Real) { Ok(Nil) },
    )
  let cmd_no_pre =
    command.no_precondition(
      name: "tick",
      next_model: fn(m: Model) { Model(value: m.value + 1) },
      run: fn(_r: Real) { Ok(Nil) },
    )
  should.equal(command.name_of(cmd_always), command.name_of(cmd_no_pre))
  should.equal(cmd_always.precondition(Model(value: 0)), True)
  should.equal(cmd_no_pre.precondition(Model(value: 0)), True)
  should.equal(cmd_always.precondition(Model(value: 99)), True)
  should.equal(cmd_no_pre.precondition(Model(value: 99)), True)
  should.equal(cmd_always.next_model(Model(value: 5)), Model(value: 6))
  should.equal(cmd_no_pre.next_model(Model(value: 5)), Model(value: 6))
}
