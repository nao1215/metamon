import gleeunit/should
import metamon/transform
import metamon/transform/dict as dict_t
import metamon/transform/list as list_t
import metamon/transform/string as string_t

pub fn identity_returns_input_test() {
  let t = transform.identity()
  should.equal(t.apply(42), 42)
  should.equal(t.name, "identity")
}

pub fn constant_ignores_input_test() {
  let t = transform.constant("k", 99)
  should.equal(t.apply(7), 99)
  should.equal(t.name, "k")
}

pub fn then_composes_in_order_test() {
  let plus_one = transform.new("+1", fn(n) { n + 1 })
  let times_two = transform.new("×2", fn(n) { n * 2 })
  let composed = transform.then(plus_one, times_two)
  // (3 + 1) * 2 = 8
  should.equal(composed.apply(3), 8)
  should.equal(composed.name, "+1 |> ×2")
}

pub fn repeat_applies_n_times_test() {
  let plus_one = transform.new("+1", fn(n) { n + 1 })
  let three_times = transform.repeat(plus_one, 3)
  should.equal(three_times.apply(0), 3)
}

pub fn repeat_zero_is_identity_test() {
  let plus_one = transform.new("+1", fn(n) { n + 1 })
  let zero = transform.repeat(plus_one, 0)
  should.equal(zero.apply(7), 7)
}

pub fn rename_keeps_behaviour_test() {
  let plus_one = transform.new("+1", fn(n) { n + 1 })
  let renamed = transform.rename(plus_one, "increment")
  should.equal(renamed.apply(2), 3)
  should.equal(renamed.name, "increment")
}

// list transforms

pub fn list_reverse_test() {
  let t = list_t.reverse()
  should.equal(t.apply([1, 2, 3]), [3, 2, 1])
}

pub fn list_dedupe_keeps_first_occurrence_test() {
  let t = list_t.dedupe()
  should.equal(t.apply([1, 2, 1, 3, 2]), [1, 2, 3])
}

pub fn list_prepend_test() {
  let t = list_t.prepend(0)
  should.equal(t.apply([1, 2]), [0, 1, 2])
}

pub fn list_append_test() {
  let t = list_t.append(99)
  should.equal(t.apply([1, 2]), [1, 2, 99])
}

pub fn list_shuffle_is_deterministic_test() {
  let t = list_t.shuffle(7)
  let input = [1, 2, 3, 4, 5, 6]
  // Same seed → same output (idempotent at the seed level).
  should.equal(t.apply(input), t.apply(input))
}

pub fn list_shuffle_preserves_multiset_test() {
  let t = list_t.shuffle(13)
  let input = [1, 2, 3, 4, 5]
  let shuffled = t.apply(input)
  // 1..5 should all still be present
  should.be_true(list_eq_as_set(shuffled, input))
}

fn list_eq_as_set(left: List(Int), right: List(Int)) -> Bool {
  case left {
    [] -> right == []
    [first, ..rest] ->
      case remove_first(first, right) {
        Ok(remaining) -> list_eq_as_set(rest, remaining)
        Error(_) -> False
      }
  }
}

fn remove_first(target: Int, items: List(Int)) -> Result(List(Int), Nil) {
  remove_first_loop(target, items, [])
}

fn remove_first_loop(
  target: Int,
  items: List(Int),
  acc: List(Int),
) -> Result(List(Int), Nil) {
  case items {
    [] -> Error(Nil)
    [first, ..rest] ->
      case first == target {
        True -> Ok(reverse_then_append(acc, rest))
        False -> remove_first_loop(target, rest, [first, ..acc])
      }
  }
}

fn reverse_then_append(left: List(Int), right: List(Int)) -> List(Int) {
  case left {
    [] -> right
    [first, ..rest] -> reverse_then_append(rest, [first, ..right])
  }
}

// string transforms

pub fn string_reverse_test() {
  let t = string_t.reverse()
  should.equal(t.apply("abc"), "cba")
}

pub fn string_lowercase_test() {
  let t = string_t.lowercase()
  should.equal(t.apply("ABC"), "abc")
}

pub fn string_uppercase_test() {
  let t = string_t.uppercase()
  should.equal(t.apply("abc"), "ABC")
}

pub fn string_trim_test() {
  let t = string_t.trim()
  should.equal(t.apply("  hi  "), "hi")
}

pub fn string_prepend_test() {
  let t = string_t.prepend(">> ")
  should.equal(t.apply("ok"), ">> ok")
}

// dict transforms

import gleam/dict

pub fn dict_insert_test() {
  let t = dict_t.insert("k", 9)
  let result = t.apply(dict.new())
  should.equal(dict.get(result, "k"), Ok(9))
}

pub fn dict_remove_test() {
  let t = dict_t.remove("k")
  let input = dict.from_list([#("k", 1), #("j", 2)])
  let result = t.apply(input)
  should.equal(dict.get(result, "k"), Error(Nil))
  should.equal(dict.get(result, "j"), Ok(2))
}

pub fn dict_shuffle_keys_preserves_equality_test() {
  let t = dict_t.shuffle_keys(99)
  let input = dict.from_list([#("a", 1), #("b", 2), #("c", 3), #("d", 4)])
  // Dict equality is order-independent, so the shuffled result is ==.
  should.equal(t.apply(input), input)
}
