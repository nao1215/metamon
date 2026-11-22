//// Per-run annotations behind `metamon.annotate`. They are shown only
//// when the property fails; the runner clears them before every run.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import metamon/internal/process_state

const annotations_key: String = "annotations"

/// Record `value`, rendered with `string.inspect`, under `label`.
pub fn annotate(label: String, value: a) -> Nil {
  // The buffer is stored newest first so adding a message is O(1);
  // `current_annotations` reverses it once.
  process_state.put(annotations_key, [
    label <> ": " <> string.inspect(value),
    ..read()
  ])
}

/// Clear the annotations. Called by the runner before each run.
pub fn reset() -> Nil {
  process_state.erase(annotations_key)
}

/// The annotations recorded since the last `reset`, oldest first.
pub fn current_annotations() -> List(String) {
  read() |> list.reverse
}

fn read() -> List(String) {
  case process_state.get(annotations_key) {
    Error(_) -> []
    Ok(raw) -> coerce_string_list(raw)
  }
}

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce_string_list(raw: Dynamic) -> List(String)
