//// Per-property coverage state behind `metamon.classify` and
//// `metamon.cover`.
////
//// The runner counts the runs of a property; `classify` and `cover`
//// count the runs that hit a label, at most once per run. A `cover`
//// requirement whose label is hit by fewer runs than its percentage
//// fails the property even when every run passed.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import metamon/internal/process_state

const counts_key: String = "coverage_counts"

const total_key: String = "coverage_total"

const requirements_key: String = "coverage_requirements"

/// Labels already hit in the current run, so a label counts once per run.
const run_hits_key: String = "coverage_run_hits"

/// A `cover` requirement: at least `target_pct` percent of the runs must
/// hit `label`. `hits` is filled in by `snapshot`.
pub type Requirement {
  Requirement(label: String, target_pct: Float, hits: Int)
}

/// The coverage state of one property: the number of runs, the hits of
/// every label, and the requirements with their hits.
pub type Snapshot {
  Snapshot(
    total: Int,
    counts: Dict(String, Int),
    requirements: List(Requirement),
  )
}

/// Count the current run as hitting `label` when `condition` is true.
pub fn classify(label: String, condition: Bool) -> Nil {
  case condition {
    False -> Nil
    True -> hit(label)
  }
}

fn hit(label: String) -> Nil {
  let run_hits = read_run_hits()
  case list.contains(run_hits, label) {
    True -> Nil
    False -> {
      process_state.put(run_hits_key, [label, ..run_hits])
      bump_count(label)
    }
  }
}

fn read_run_hits() -> List(String) {
  case process_state.get(run_hits_key) {
    Error(_) -> []
    Ok(raw) -> coerce_string_list(raw)
  }
}

/// Like `classify`, and require `label` to be hit by at least
/// `target_pct` percent of the runs. The first call for a label sets its
/// target.
///
/// Panics when `target_pct` is outside `[0.0, 100.0]` or NaN.
pub fn cover(target_pct: Float, label: String, condition: Bool) -> Nil {
  // NaN compares False against every operand, so this rejects it too.
  case target_pct >=. 0.0 && target_pct <=. 100.0 {
    True -> Nil
    False ->
      panic as {
        "metamon.cover: at_least must be in [0.0, 100.0] (got "
        <> float.to_string(target_pct)
        <> ")"
      }
  }
  ensure_requirement(label, target_pct)
  classify(label, condition)
}

/// Clear the coverage state. Called by the runner at the start of each
/// property.
pub fn reset() -> Nil {
  process_state.erase(counts_key)
  process_state.erase(total_key)
  process_state.erase(requirements_key)
  process_state.erase(run_hits_key)
  Nil
}

/// Read the current coverage state.
pub fn snapshot() -> Snapshot {
  let counts = read_counts()
  Snapshot(
    total: read_total(),
    counts: counts,
    requirements: enriched_requirements(counts),
  )
}

/// `(hits / total) * 100`, or `0.0` when `total` is zero.
pub fn actual_pct(hits: Int, total: Int) -> Float {
  case total <= 0 {
    True -> 0.0
    False -> int.to_float(hits) /. int.to_float(total) *. 100.0
  }
}

/// Count one run of the property. Called by the runner once per
/// generated input, so the percentages are over runs, not over calls.
pub fn count_run() -> Nil {
  process_state.erase(run_hits_key)
  process_state.put(total_key, read_total() + 1)
}

/// The first requirement whose label is hit by fewer runs than its
/// target, if any.
pub fn first_shortfall(snap: Snapshot) -> Option(Requirement) {
  case snap.total <= 0 {
    True -> None
    False ->
      list.find(snap.requirements, fn(req: Requirement) {
        actual_pct(req.hits, snap.total) <. req.target_pct
      })
      |> option.from_result
  }
}

fn read_total() -> Int {
  case process_state.get(total_key) {
    Error(_) -> 0
    Ok(raw) -> coerce_int(raw)
  }
}

fn bump_count(label: String) -> Nil {
  let next =
    dict.upsert(read_counts(), label, fn(existing) {
      case existing {
        Some(n) -> n + 1
        None -> 1
      }
    })
  process_state.put(counts_key, next)
}

fn read_counts() -> Dict(String, Int) {
  case process_state.get(counts_key) {
    Error(_) -> dict.new()
    Ok(raw) -> coerce_string_int_dict(raw)
  }
}

fn ensure_requirement(label: String, target_pct: Float) -> Nil {
  let current = read_requirements()
  case list.any(current, fn(req: Requirement) { req.label == label }) {
    True -> Nil
    False ->
      process_state.put(requirements_key, [
        Requirement(label: label, target_pct: target_pct, hits: 0),
        ..current
      ])
  }
}

fn read_requirements() -> List(Requirement) {
  case process_state.get(requirements_key) {
    Error(_) -> []
    Ok(raw) -> coerce_requirements(raw)
  }
}

fn enriched_requirements(counts: Dict(String, Int)) -> List(Requirement) {
  read_requirements()
  |> list.map(fn(req: Requirement) {
    let hits = case dict.get(counts, req.label) {
      Ok(n) -> n
      Error(_) -> 0
    }
    Requirement(..req, hits: hits)
  })
}

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce_int(raw: Dynamic) -> Int

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce_string_list(raw: Dynamic) -> List(String)

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce_string_int_dict(raw: Dynamic) -> Dict(String, Int)

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../../metamon_ffi.mjs", "identity")
fn coerce_requirements(raw: Dynamic) -> List(Requirement)
