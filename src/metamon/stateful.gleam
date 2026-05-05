//// Run a sequence of `Command(model, real)` against an initial
//// `(model, real)` pair, asserting that every command's
//// `precondition` holds against the model and that `run` against
//// the real returns `Ok(Nil)`.
////
//// This is the minimum surface needed for model-based testing. It
//// intentionally does not generate command sequences: callers
//// construct the list themselves (or with `metamon.forall_with` over
//// a list-of-commands generator). Shrinking command sequences and
//// scheduler-based parallelism are out of scope for this minimum;
//// the explicit list-driven flow is enough to catch model/real
//// drift in straightforward state machines.

import gleam/int
import gleam/list
import gleam/string
import metamon/command.{type Command}

/// Outcome of running a command sequence.
pub type Outcome(model) {
  /// All commands whose preconditions held passed against the real
  /// world. The final model state is reported for inspection.
  Passed(final_model: model, ran: Int, skipped: Int)
  /// The i-th command (zero-indexed) failed: either its real-side
  /// `run` returned `Error` or no command of the original list had
  /// a satisfied precondition (in which case `index = -1`).
  Failed(
    index: Int,
    command_name: String,
    reason: String,
    model_at_failure: model,
  )
}

/// Run `commands` left-to-right starting from `initial_model` and
/// `initial_real`. Commands whose preconditions fail are skipped
/// (counted but not run). The first real-side `Error(_)` halts the
/// sequence and is returned as `Failed`.
pub fn run(
  initial_model: model,
  initial_real: real,
  commands: List(Command(model, real)),
) -> Outcome(model) {
  run_loop(initial_model, initial_real, commands, 0, 0)
}

fn run_loop(
  model: model,
  real: real,
  commands: List(Command(model, real)),
  index: Int,
  skipped: Int,
) -> Outcome(model) {
  case commands {
    [] -> Passed(final_model: model, ran: index - skipped, skipped: skipped)
    [cmd, ..rest] ->
      case cmd.precondition(model) {
        False -> run_loop(model, real, rest, index + 1, skipped + 1)
        True ->
          case cmd.run(real) {
            Error(reason) ->
              Failed(
                index: index,
                command_name: cmd.name,
                reason: reason,
                model_at_failure: model,
              )
            Ok(Nil) ->
              run_loop(cmd.next_model(model), real, rest, index + 1, skipped)
          }
      }
  }
}

/// Convenience: assert that the outcome is `Passed`. On `Failed`,
/// panic with a structured message that mirrors the regular failure
/// report style.
pub fn assert_passed(outcome: Outcome(model)) -> Nil {
  case outcome {
    Passed(_, _, _) -> Nil
    Failed(index, name, reason, _) ->
      panic_with_message(
        string.concat([
          "× stateful command failed\n  command:    `",
          name,
          "`\n  index:      ",
          int.to_string(index),
          "\n  reason:     ",
          reason,
        ]),
      )
  }
}

/// Names of all commands in the sequence, in order. Useful for the
/// stateful test's own failure messages.
pub fn names_of(commands: List(Command(model, real))) -> List(String) {
  list.map(commands, command.name_of)
}

fn panic_with_message(message: String) -> Nil {
  panic as message
}
