//// Stateful / model-based testing primitives.
////
//// A `Command(model, real)` represents one transition that can be
//// applied to two parallel worlds:
////
////   * **model**: a pure description of the expected state (typically
////     a record or a `Dict`). The `next_model` step says how the
////     command updates this expected state.
////   * **real**: the system under test (a database connection, a
////     stateful module, an in-memory cache). The `run` step performs
////     the command on the real world and returns `Ok(Nil)` on
////     success or `Error(reason)` when an invariant is violated.
////
//// The `precondition` decides whether the command can fire in the
//// current model state; the runner skips commands whose preconditions
//// are false.
////
//// See `metamon/stateful` for the runner that drives a list of
//// commands against an initial `(model, real)` pair.

/// A single transition in a model-based test.
pub type Command(model, real) {
  Command(
    name: String,
    precondition: fn(model) -> Bool,
    next_model: fn(model) -> model,
    run: fn(real) -> Result(Nil, String),
  )
}

/// Construct a command. `name` is shown in failure reports.
pub fn new(
  name name: String,
  precondition pre: fn(model) -> Bool,
  next_model next: fn(model) -> model,
  run run: fn(real) -> Result(Nil, String),
) -> Command(model, real) {
  Command(name: name, precondition: pre, next_model: next, run: run)
}

/// A command that always passes its precondition.
pub fn always(
  name name: String,
  next_model next: fn(model) -> model,
  run run: fn(real) -> Result(Nil, String),
) -> Command(model, real) {
  Command(name: name, precondition: fn(_m) { True }, next_model: next, run: run)
}

/// Get the command's user-facing name.
pub fn name_of(cmd: Command(model, real)) -> String {
  cmd.name
}
