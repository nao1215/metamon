//// Run a property and catch its panic, so a failing `assert`,
//// `let assert`, `panic`, Erlang error or JavaScript exception becomes a
//// value the runner can shrink and report.

import gleam/dynamic.{type Dynamic}

/// The result of running a function that may panic.
pub type Attempt(a) {
  Returned(value: a)
  /// The panic message, or the formatted value of an error raised
  /// outside Gleam.
  Panicked(message: String)
}

/// Run `thunk` and return its value, or the message of its panic.
pub fn attempt(thunk: fn() -> a) -> Attempt(a) {
  case run(thunk) {
    #(True, message) -> Panicked(coerce(message))
    #(False, value) -> Returned(coerce(value))
  }
}

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "../../metamon_ffi.mjs", "capture_panic")
fn run(thunk: fn() -> a) -> #(Bool, Dynamic)

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce(value: Dynamic) -> b
