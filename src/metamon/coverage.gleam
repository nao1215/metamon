//// Coverage and classification primitives for property-based tests.
////
//// `classify` tags a generated input with a label so the runner can
//// report the distribution at the end of a successful run.
//// `cover` additionally asserts a minimum percentage — if fewer
//// inputs hit the label than required, the property fails even when
//// every individual run passed.
//// `collect` records the value itself (via a user-supplied `show`)
//// for histogram-style reporting.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import metamon/internal/process_state

const counts_key: String = "coverage_counts"

const total_key: String = "coverage_total"

const requirements_key: String = "coverage_requirements"

const collected_key: String = "coverage_collected"

/// One coverage requirement. A requirement is met when the label's
/// hit count is at least `target_pct`% of total runs (Pct kind) or
/// at least `min_hits` absolute occurrences (Count kind).
pub type Requirement {
  Requirement(label: String, kind: RequirementKind, hits: Int)
}

/// Distinguishes percentage-based from absolute-count requirements
/// so the runner knows which threshold to compare against.
pub type RequirementKind {
  /// At least `target_pct`% of inputs must hit the label.
  Pct(target_pct: Float)
  /// At least `min_hits` inputs must hit the label.
  Count(min_hits: Int)
}

/// Backwards-compat helper: extract the percentage target if the
/// requirement is a Pct one, otherwise compute it from the
/// minimum-count requirement and the recorded total. Used by the
/// failure formatter and the `target_pct` accessor in older code.
pub fn target_pct_of(req: Requirement, total: Int) -> Float {
  case req.kind {
    Pct(target) -> target
    Count(min) ->
      case total <= 0 {
        True -> 0.0
        False -> int.to_float(min) /. int.to_float(total) *. 100.0
      }
  }
}

/// Snapshot of the coverage state for one property run.
pub type Snapshot {
  Snapshot(
    total: Int,
    counts: Dict(String, Int),
    requirements: List(Requirement),
    collected: Dict(String, Int),
  )
}

/// Tag the current input with `label` if `condition` is true. Only
/// labelled hits are counted, but every call to `classify` advances
/// the total-runs denominator.
pub fn classify(label: String, condition: Bool) -> Nil {
  bump_total()
  case condition {
    False -> Nil
    True -> bump_count(counts_key, label)
  }
}

/// Like `classify` but also asserts that the label hits at least
/// `target_pct` percent of all inputs in the run.
pub fn cover(target_pct: Float, label: String, condition: Bool) -> Nil {
  bump_total()
  ensure_pct_requirement(label, target_pct)
  case condition {
    False -> Nil
    True -> bump_count(counts_key, label)
  }
}

/// Absolute-count variant of `cover`: assert that the label is hit
/// at least `min_hits` times across the entire run. Useful when you
/// know the exact number of edge cases that should fire (e.g. "at
/// least 3 inputs trigger the empty-list path").
pub fn cover_at_least(min_hits: Int, label: String, condition: Bool) -> Nil {
  bump_total()
  ensure_count_requirement(label, min_hits)
  case condition {
    False -> Nil
    True -> bump_count(counts_key, label)
  }
}

/// Tag the current input as belonging to a mutually-exclusive
/// `bucket` within `group`. Buckets are recorded as
/// `"<group>=<bucket>"` so the failure report can show distribution
/// by group at a glance. Calling `classify_in_bucket` more than once
/// per input within the same `group` is a programming error and is
/// silently kept (the runner does not enforce mutual exclusion).
pub fn classify_in_bucket(group: String, bucket: String) -> Nil {
  classify(group <> "=" <> bucket, True)
}

/// Render `value` via `show` and add the result to the histogram of
/// collected values.
pub fn collect(value: a, show: fn(a) -> String) -> Nil {
  bump_total()
  bump_count(collected_key, show(value))
}

/// Reset all coverage state. Called by the runner at the start of
/// each property.
pub fn reset() -> Nil {
  process_state.erase(counts_key)
  process_state.erase(total_key)
  process_state.erase(requirements_key)
  process_state.erase(collected_key)
  Nil
}

/// Read the current coverage snapshot.
pub fn snapshot() -> Snapshot {
  let total = read_total()
  let counts = read_dict(counts_key)
  let requirements = enriched_requirements(counts)
  let collected = read_dict(collected_key)
  Snapshot(
    total: total,
    counts: counts,
    requirements: requirements,
    collected: collected,
  )
}

/// Find requirements whose actual coverage falls short of the target.
/// Pct requirements are checked against `actual_pct`; Count
/// requirements are checked against the absolute hit count.
pub fn shortfalls(snap: Snapshot) -> List(Requirement) {
  case snap.total <= 0 {
    True -> []
    False ->
      list.filter(snap.requirements, fn(req: Requirement) {
        case req.kind {
          Pct(target) -> actual_pct(req.hits, snap.total) <. target
          Count(min) -> req.hits < min
        }
      })
  }
}

/// `(hits / total) * 100`, returning `0.0` if `total` is zero.
pub fn actual_pct(hits: Int, total: Int) -> Float {
  case total <= 0 {
    True -> 0.0
    False -> int.to_float(hits) /. int.to_float(total) *. 100.0
  }
}

fn bump_total() -> Nil {
  let updated = read_total() + 1
  process_state.put(total_key, updated)
  Nil
}

fn read_total() -> Int {
  case process_state.get(total_key) {
    Error(_) -> 0
    Ok(raw) -> coerce_int(raw)
  }
}

fn bump_count(key: String, label: String) -> Nil {
  let counts = read_dict(key)
  let next =
    dict.upsert(counts, label, fn(existing) {
      case existing {
        Some(n) -> n + 1
        None -> 1
      }
    })
  process_state.put(key, next)
  Nil
}

fn read_dict(key: String) -> Dict(String, Int) {
  case process_state.get(key) {
    Error(_) -> dict.new()
    Ok(raw) -> coerce_string_int_dict(raw)
  }
}

fn ensure_pct_requirement(label: String, target_pct: Float) -> Nil {
  ensure_requirement(label, Pct(target_pct))
}

fn ensure_count_requirement(label: String, min_hits: Int) -> Nil {
  ensure_requirement(label, Count(min_hits))
}

fn ensure_requirement(label: String, kind: RequirementKind) -> Nil {
  let current = read_requirements()
  let already = list.any(current, fn(req: Requirement) { req.label == label })
  case already {
    True -> Nil
    False -> {
      let updated = [Requirement(label: label, kind: kind, hits: 0), ..current]
      process_state.put(requirements_key, updated)
      Nil
    }
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
    Requirement(label: req.label, kind: req.kind, hits: hits)
  })
}

/// Read a single label's hit count.
pub fn hits_for(snap: Snapshot, label: String) -> Int {
  case dict.get(snap.counts, label) {
    Ok(n) -> n
    Error(_) -> 0
  }
}

/// Convenience accessor used by the runner / report.
pub fn requirements_of(snap: Snapshot) -> List(Requirement) {
  snap.requirements
}

/// Convenience accessor used by the runner / report.
pub fn collected_of(snap: Snapshot) -> Dict(String, Int) {
  snap.collected
}

/// `Some(req)` when at least one shortfall exists, otherwise `None`.
pub fn first_shortfall(snap: Snapshot) -> Option(Requirement) {
  case shortfalls(snap) {
    [] -> None
    [first, ..] -> Some(first)
  }
}

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../metamon_ffi.mjs", "identity")
fn coerce_int(raw: Dynamic) -> Int

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../metamon_ffi.mjs", "identity")
fn coerce_string_int_dict(raw: Dynamic) -> Dict(String, Int)

@external(erlang, "metamon_ffi", "identity")
@external(javascript, "../metamon_ffi.mjs", "identity")
fn coerce_requirements(raw: Dynamic) -> List(Requirement)
