import gleam/dict
import gleeunit/should
import metamon/coverage

pub fn snapshot_starts_empty_test() {
  coverage.reset()
  let snap = coverage.snapshot()
  should.equal(snap.total, 0)
  should.equal(coverage.requirements_of(snap), [])
}

pub fn classify_increments_count_test() {
  coverage.reset()
  coverage.classify("zero", True)
  coverage.classify("zero", True)
  coverage.classify("zero", False)
  let snap = coverage.snapshot()
  should.equal(snap.total, 3)
  should.equal(coverage.hits_for(snap, "zero"), 2)
}

pub fn cover_records_a_requirement_test() {
  coverage.reset()
  coverage.cover(50.0, "even", True)
  coverage.cover(50.0, "even", False)
  coverage.cover(50.0, "even", True)
  coverage.cover(50.0, "even", True)
  let snap = coverage.snapshot()
  let assert [req] = coverage.requirements_of(snap)
  should.equal(req.label, "even")
  should.equal(req.kind, coverage.Pct(50.0))
  should.equal(req.hits, 3)
}

pub fn shortfalls_flags_unmet_requirements_test() {
  coverage.reset()
  coverage.cover(80.0, "rare", True)
  coverage.cover(80.0, "rare", False)
  coverage.cover(80.0, "rare", False)
  let snap = coverage.snapshot()
  let bad = coverage.shortfalls(snap)
  should.equal(bad |> count_list(), 1)
}

fn count_list(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + count_list(rest)
  }
}

pub fn shortfalls_empty_when_target_met_test() {
  coverage.reset()
  coverage.cover(20.0, "common", True)
  coverage.cover(20.0, "common", True)
  coverage.cover(20.0, "common", False)
  coverage.cover(20.0, "common", False)
  let snap = coverage.snapshot()
  should.equal(coverage.shortfalls(snap), [])
}

pub fn collect_buckets_values_test() {
  coverage.reset()
  coverage.collect("a", fn(s: String) { s })
  coverage.collect("a", fn(s: String) { s })
  coverage.collect("b", fn(s: String) { s })
  let snap = coverage.snapshot()
  let collected = coverage.collected_of(snap)
  should.equal(dict.get(collected, "a"), Ok(2))
  should.equal(dict.get(collected, "b"), Ok(1))
}

pub fn actual_pct_zero_when_total_zero_test() {
  should.equal(coverage.actual_pct(0, 0), 0.0)
  should.equal(coverage.actual_pct(50, 100), 50.0)
}

// ---------- Count-kind requirement ----------

pub fn cover_at_least_records_count_kind_test() {
  coverage.reset()
  coverage.cover_at_least(2, "primes", True)
  coverage.cover_at_least(2, "primes", False)
  coverage.cover_at_least(2, "primes", True)
  let snap = coverage.snapshot()
  let assert [req] = coverage.requirements_of(snap)
  should.equal(req.label, "primes")
  should.equal(req.kind, coverage.Count(2))
  should.equal(req.hits, 2)
}

pub fn cover_at_least_meets_target_test() {
  coverage.reset()
  coverage.cover_at_least(2, "ok", True)
  coverage.cover_at_least(2, "ok", True)
  coverage.cover_at_least(2, "ok", True)
  let snap = coverage.snapshot()
  should.equal(coverage.shortfalls(snap), [])
}

pub fn cover_at_least_falls_short_test() {
  coverage.reset()
  coverage.cover_at_least(5, "ok", True)
  coverage.cover_at_least(5, "ok", False)
  coverage.cover_at_least(5, "ok", False)
  let snap = coverage.snapshot()
  case coverage.shortfalls(snap) {
    [req] -> should.equal(req.kind, coverage.Count(5))
    _ -> should.fail()
  }
}

pub fn classify_in_bucket_groups_labels_test() {
  coverage.reset()
  coverage.classify_in_bucket("size", "small")
  coverage.classify_in_bucket("size", "small")
  coverage.classify_in_bucket("size", "large")
  let snap = coverage.snapshot()
  should.equal(coverage.hits_for(snap, "size=small"), 2)
  should.equal(coverage.hits_for(snap, "size=large"), 1)
}
