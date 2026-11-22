//// The failure report's diff block compares the outputs element by
//// element, and string literals are split correctly.

import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import metamon/internal/diff.{Differ, IndexedDiff, ListDiff, Same, TupleDiff}
import metamon/relation
import metamon/transform
import test_helpers

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  assert panicked
  message
}

fn plus_one_mr() -> metamon.Mr(Int, a) {
  metamon.mr(
    name: "invariant_under_plus_one",
    transform: transform.new("+1", fn(n) { n + 1 }),
    relation: relation.equal(),
  )
}

pub fn report_diffs_list_outputs_per_index_test() {
  let text =
    failure_text(fn() {
      metamon.forall_morph(generator.return(3), plus_one_mr(), fn(n) {
        [1, 2, n]
      })
    })
  assert string.contains(text, "    [#2]\n      - 3\n      + 4")
  assert string.contains(text, "    [#0]\n      = 1")
}

pub fn report_diffs_tuple_outputs_per_index_test() {
  let text =
    failure_text(fn() {
      metamon.forall_morph(generator.return(3), plus_one_mr(), fn(n) {
        #("x", n)
      })
    })
  assert string.contains(text, "    #.1\n      - 3\n      + 4")
}

pub fn report_diff_escapes_strings_once_test() {
  let text =
    failure_text(fn() {
      metamon.forall_morph(generator.return(3), plus_one_mr(), fn(n) {
        string.repeat("\"", n)
      })
    })
  assert string.contains(
    text,
    "    - \"\\\"\\\"\\\"\"\n    + \"\\\"\\\"\\\"\\\"\"",
  )
}

pub fn string_elements_with_separators_stay_whole_test() {
  assert inspected(["a,b", "]"], ["a,c", "]"])
    == ListDiff([
      IndexedDiff(0, Differ("\"a,b\"", "\"a,c\"")),
      IndexedDiff(1, Same("\"]\"")),
    ])
  assert inspected(#("(", "\"x,"), #("(", "\"y,"))
    == TupleDiff([
      IndexedDiff(0, Same("\"(\"")),
      IndexedDiff(1, Differ("\"\\\"x,\"", "\"\\\"y,\"")),
    ])
}

pub fn list_diff_has_one_item_per_element_test() {
  metamon.forall(
    generator.tuple2(
      generator.list_of(
        generator.string_ascii(range.constant(0, 4)),
        range.constant(0, 4),
      ),
      generator.list_of(
        generator.string_ascii(range.constant(0, 4)),
        range.constant(0, 4),
      ),
    ),
    fn(pair) {
      let #(left, right) = pair
      assert case left == right, inspected(left, right) {
        True, Same(_) -> True
        False, ListDiff(items) ->
          list.length(items) == int.max(list.length(left), list.length(right))
        _, _ -> False
      }
    },
  )
}

pub fn bit_array_elements_stay_whole_test() {
  // Bytes that are not UTF-8, so both targets render `<<...>>`.
  assert inspected([<<255, 2>>, <<200>>], [<<255, 2>>, <<201>>])
    == ListDiff([
      IndexedDiff(0, Same("<<255, 2>>")),
      IndexedDiff(1, Differ("<<200>>", "<<201>>")),
    ])
}

fn inspected(left: a, right: a) -> diff.Diff {
  diff.diff_inspected(string.inspect(left), string.inspect(right))
}
