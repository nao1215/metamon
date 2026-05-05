//// Add per-property context that is only displayed when the property
//// fails. Successful runs discard all annotations so the cost is zero
//// in the happy path.
////
//// The runner clears state at the start of every run and reads any
//// remaining state on failure.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import metamon/internal/process_state

const annotations_key: String = "annotations"

const footnotes_key: String = "footnotes"

/// Add a free-form message to the current property's annotation buffer.
/// Successful runs discard the buffer, so this is cheap.
pub fn annotate(message: String) -> Nil {
  push(annotations_key, message)
}

/// Pretty-print `value` and add it to the annotation buffer with a
/// human-readable label. The output uses Gleam's `string.inspect` so it
/// works on any type.
pub fn annotate_value(label: String, value: a) -> Nil {
  let rendered = label <> ": " <> string.inspect(value)
  push(annotations_key, rendered)
}

/// Add a short message to the footnote buffer (printed at the bottom
/// of the failure report).
pub fn footnote(message: String) -> Nil {
  push(footnotes_key, message)
}

/// Clear annotation and footnote buffers. Called by the runner before
/// each property run.
pub fn reset() -> Nil {
  process_state.erase(annotations_key)
  process_state.erase(footnotes_key)
  Nil
}

/// Read the annotations recorded since the last `reset`. Order is the
/// order in which they were registered.
pub fn current_annotations() -> List(String) {
  read(annotations_key)
}

/// Read the footnotes recorded since the last `reset`.
pub fn current_footnotes() -> List(String) {
  read(footnotes_key)
}

fn push(key: String, message: String) -> Nil {
  let updated = [message, ..read(key)]
  process_state.put(key, updated)
  Nil
}

fn read(key: String) -> List(String) {
  case process_state.get(key) {
    Error(_) -> []
    Ok(raw) -> coerce_string_list(raw) |> list.reverse()
  }
}

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../metamon_ffi.mjs", "identity")
fn coerce_string_list(raw: Dynamic) -> List(String)
