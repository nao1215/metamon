//// Shrink strategy verification for the built-in generators.
////
//// Inspired by:
////   - mooreryan/gleam_qcheck — `test/qcheck/tree_test.gleam`,
////     `test/qcheck/gen_int_test.gleam`, `test/qcheck/gen_list_test.gleam`
////     (Apache-2.0 / MIT)
////   - hedgehogqa/haskell-hedgehog — `src/Hedgehog/Internal/Shrink.hs`
////     (BSD-3-Clause)
////   - proptest-rs/proptest — value-tree contraction tests
////     (Apache-2.0 / MIT)
////
//// Every test body below is an independent re-implementation against
//// the metamon API. No upstream source code has been copied.

import gleam/list
import gleeunit/should
import metamon/generator/shrink

// ---------- int_toward ----------

pub fn int_toward_origin_returns_empty_when_already_at_origin_test() {
  should.equal(shrink.int_toward(0, 0), [])
  should.equal(shrink.int_toward(7, 7), [])
  should.equal(shrink.int_toward(-3, -3), [])
}

pub fn int_toward_origin_first_candidate_is_origin_test() {
  // The classic QuickCheck halving: try the origin first so a small
  // failing example is found in a single step when the bug also
  // triggers at the origin.
  let candidates = shrink.int_toward(0, 64)
  case candidates {
    [first, ..] -> should.equal(first, 0)
    [] -> should.fail()
  }
}

pub fn int_toward_origin_distance_is_monotonically_increasing_test() {
  // After the initial origin candidate, each subsequent candidate
  // moves closer to the original value (i.e. distance to origin
  // increases). This is the dual of "shrink toward origin": we walk
  // from the smallest plausible counter-example back up toward the
  // original failing input.
  let origin = 0
  let candidates = shrink.int_toward(origin, 100)
  let _ =
    list.fold(candidates, -1, fn(prev_distance, next) {
      let next_distance = abs(next - origin)
      case next_distance >= prev_distance {
        True -> next_distance
        False -> {
          should.fail()
          next_distance
        }
      }
    })
  Nil
}

fn abs(value: Int) -> Int {
  case value < 0 {
    True -> -value
    False -> value
  }
}

pub fn int_toward_works_with_non_zero_origin_test() {
  let candidates = shrink.int_toward(10, 50)
  // The first candidate must be at the origin.
  case candidates {
    [first, ..] -> should.equal(first, 10)
    [] -> should.fail()
  }
  // No candidate should overshoot the origin (i.e. fall below 10).
  list.each(candidates, fn(c) { should.be_true(c >= 10 && c <= 50) })
}

pub fn int_toward_negative_value_test() {
  let candidates = shrink.int_toward(0, -64)
  case candidates {
    [first, ..] -> should.equal(first, 0)
    [] -> should.fail()
  }
  // All candidates lie between value (-64) and origin (0).
  list.each(candidates, fn(c) { should.be_true(c >= -64 && c <= 0) })
}

pub fn int_toward_does_not_repeat_test() {
  // A naïve halving (e.g. dividing by 2 with truncation toward zero)
  // can emit duplicates near the boundary; the implementation
  // dedupes. We assert that no value appears twice.
  let candidates = shrink.int_toward(0, 7)
  let unique_count =
    candidates
    |> deduplicate()
    |> count()
  should.equal(count(candidates), unique_count)
}

fn deduplicate(items: List(Int)) -> List(Int) {
  loop_dedupe(items, [], [])
}

fn loop_dedupe(items: List(Int), seen: List(Int), acc: List(Int)) -> List(Int) {
  case items {
    [] -> list.reverse(acc)
    [first, ..rest] ->
      case list.contains(seen, first) {
        True -> loop_dedupe(rest, seen, acc)
        False -> loop_dedupe(rest, [first, ..seen], [first, ..acc])
      }
  }
}

fn count(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + count(rest)
  }
}

// ---------- list_drops ----------

pub fn list_drops_includes_empty_for_non_empty_input_test() {
  // The most aggressive drop is the full list — the drop strategy
  // must include the empty list so the runner can find "the empty
  // list also fails" counter-examples quickly.
  let drops = shrink.list_drops([1, 2, 3, 4])
  should.be_true(list.contains(drops, []))
}

pub fn list_drops_for_empty_input_is_empty_test() {
  // Nothing to drop from an empty list.
  should.equal(shrink.list_drops([]), [])
}

pub fn list_drops_includes_short_alternatives_test() {
  // A four-element list should suggest at least one shorter list of
  // length ≥ 1 (i.e. not just the full drop).
  let drops = shrink.list_drops([1, 2, 3, 4])
  let has_shorter =
    list.any(drops, fn(d) {
      let len = count(d)
      len > 0 && len < 4
    })
  should.be_true(has_shorter)
}

pub fn list_drops_produces_only_sub_lists_of_input_test() {
  // Every candidate must consist of elements from the original list,
  // in original relative order.
  let original = [1, 2, 3, 4, 5]
  let drops = shrink.list_drops(original)
  list.each(drops, fn(candidate) {
    should.be_true(is_in_order_subsequence(candidate, original))
  })
}

fn is_in_order_subsequence(sub: List(Int), full: List(Int)) -> Bool {
  case sub, full {
    [], _ -> True
    [_, ..], [] -> False
    [s, ..rest_sub], [f, ..rest_full] ->
      case s == f {
        True -> is_in_order_subsequence(rest_sub, rest_full)
        False -> is_in_order_subsequence(sub, rest_full)
      }
  }
}
