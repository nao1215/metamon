//// Thin wrapper around the FFI-backed per-process state used by
//// `metamon/annotate` and `metamon/coverage`.
////
//// On the BEAM the underlying storage is the process dictionary so
//// each gleeunit test process is automatically isolated; on the
//// JavaScript target the storage is a single module-level Map and the
//// runner is responsible for clearing it between runs.
////
//// The FFI surface is intentionally minimal: get / put / erase / keys.
//// All type-safe usage lives in the modules above this one.

import gleam/dynamic.{type Dynamic}

/// Store `value` under `key` in per-process state.
@external(erlang, "metamon_ffi", "state_put")
@external(javascript, "../../metamon_ffi.mjs", "state_put")
pub fn put(key: String, value: a) -> Nil

/// Read the value stored under `key`, or `Error(Nil)` if absent.
/// Callers must coerce the `Dynamic` themselves; metamon's runner
/// trusts the keys it owns.
@external(erlang, "metamon_ffi", "state_get")
@external(javascript, "../../metamon_ffi.mjs", "state_get")
pub fn get(key: String) -> Result(Dynamic, Nil)

/// Remove the entry for `key`. Idempotent.
@external(erlang, "metamon_ffi", "state_erase")
@external(javascript, "../../metamon_ffi.mjs", "state_erase")
pub fn erase(key: String) -> Nil

/// List every key currently stored. Used by tests; never used by
/// the runner itself.
@external(erlang, "metamon_ffi", "state_keys")
@external(javascript, "../../metamon_ffi.mjs", "state_keys")
pub fn keys() -> List(String)
