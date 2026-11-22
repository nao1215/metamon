//// Run a property and catch its panic, so a failing `assert`,
//// `let assert`, `panic`, Erlang error or JavaScript exception becomes a
//// value the runner can shrink and report.

import gleam/option.{type Option, None, Some}

/// Run `thunk` and return the message of its panic, or `None` when it
/// returns. An error raised outside Gleam gives its formatted value.
pub fn capture_panic(thunk: fn() -> Nil) -> Option(String) {
  case run(thunk) {
    #(True, message) -> Some(message)
    #(False, _) -> None
  }
}

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "../../metamon_ffi.mjs", "capture_panic")
fn run(thunk: fn() -> Nil) -> #(Bool, String)
