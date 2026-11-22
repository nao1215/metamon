import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import metamon/internal/coverage
import test_helpers

pub fn snapshot_starts_empty_test() {
  coverage.reset()
  let snap = coverage.snapshot()
  should.equal(snap.total, 0)
  should.equal(snap.requirements, [])
}

// The runner calls `count_run` once per run, and a label counts once per
// run; these tests stand in for the runner with one run per call.

pub fn classify_increments_count_test() {
  coverage.reset()
  coverage.count_run()
  coverage.classify("zero", True)
  coverage.count_run()
  coverage.classify("zero", True)
  coverage.count_run()
  coverage.classify("zero", False)
  let snap = coverage.snapshot()
  should.equal(snap.total, 3)
  should.equal(hits(snap, "zero"), 2)
}

pub fn cover_records_a_requirement_test() {
  coverage.reset()
  coverage.count_run()
  coverage.cover(50.0, "even", True)
  coverage.count_run()
  coverage.cover(50.0, "even", False)
  coverage.count_run()
  coverage.cover(50.0, "even", True)
  coverage.count_run()
  coverage.cover(50.0, "even", True)
  let snap = coverage.snapshot()
  let assert [req] = snap.requirements
  should.equal(req.label, "even")
  should.equal(req.target_pct, 50.0)
  should.equal(req.hits, 3)
}

pub fn shortfalls_flags_unmet_requirements_test() {
  coverage.reset()
  coverage.count_run()
  coverage.cover(80.0, "rare", True)
  coverage.count_run()
  coverage.cover(80.0, "rare", False)
  coverage.count_run()
  coverage.cover(80.0, "rare", False)
  let snap = coverage.snapshot()
  let assert Some(req) = coverage.first_shortfall(snap)
  should.equal(req.label, "rare")
}

pub fn shortfalls_empty_when_target_met_test() {
  coverage.reset()
  coverage.count_run()
  coverage.cover(20.0, "common", True)
  coverage.count_run()
  coverage.cover(20.0, "common", True)
  coverage.count_run()
  coverage.cover(20.0, "common", False)
  coverage.count_run()
  coverage.cover(20.0, "common", False)
  let snap = coverage.snapshot()
  should.equal(coverage.first_shortfall(snap), None)
}

pub fn actual_pct_zero_when_total_zero_test() {
  should.equal(coverage.actual_pct(0, 0), 0.0)
  should.equal(coverage.actual_pct(50, 100), 50.0)
}

// ---------- target_pct validation ----------

pub fn cover_panics_on_negative_target_pct_test() {
  coverage.reset()
  let #(panicked, message) =
    test_helpers.capture_panic(fn() { coverage.cover(-1.0, "neg", True) })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.cover"))
  should.be_true(string.contains(message, "[0.0, 100.0]"))
}

pub fn cover_panics_just_over_100_test() {
  coverage.reset()
  let #(panicked, message) =
    test_helpers.capture_panic(fn() {
      coverage.cover(100.0000001, "over", True)
    })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.cover"))
  should.be_true(string.contains(message, "[0.0, 100.0]"))
}

pub fn cover_accepts_zero_boundary_test() {
  coverage.reset()
  // 0.0 is the lower boundary and must be accepted.
  coverage.count_run()
  coverage.cover(0.0, "edge_lo", True)
  let snap = coverage.snapshot()
  should.equal(hits(snap, "edge_lo"), 1)
}

pub fn cover_accepts_100_boundary_test() {
  coverage.reset()
  // 100.0 is the upper boundary and must be accepted.
  coverage.count_run()
  coverage.cover(100.0, "edge_hi", True)
  let snap = coverage.snapshot()
  should.equal(hits(snap, "edge_hi"), 1)
}

fn hits(snap: coverage.Snapshot, label: String) -> Int {
  case dict.get(snap.counts, label) {
    Ok(n) -> n
    Error(Nil) -> 0
  }
}
