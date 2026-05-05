import gleam/string
import gleeunit/should
import metamon/diff.{Added, Common, Differ, Removed, Same}

pub fn equal_values_collapse_to_same_test() {
  let d = diff.diff(42, 42)
  case d {
    Same(_) -> Nil
    _ -> should.fail()
  }
}

pub fn unequal_atoms_render_as_differ_test() {
  let d = diff.diff(1, 2)
  case d {
    Differ(left: l, right: r) -> {
      should.equal(l, "1")
      should.equal(r, "2")
    }
    _ -> should.fail()
  }
}

pub fn list_of_ints_diffs_per_index_test() {
  let d = diff.diff([1, 2, 3], [1, 9, 3])
  let rendered = diff.render(d)
  // Expect a difference at index 1 (`2` vs `9`).
  should.be_true(string.contains(rendered, "[#1]"))
  should.be_true(string.contains(rendered, "- 2"))
  should.be_true(string.contains(rendered, "+ 9"))
}

pub fn list_length_mismatch_shows_padding_test() {
  let d = diff.diff([1, 2], [1, 2, 3])
  let rendered = diff.render(d)
  should.be_true(string.contains(rendered, "+ 3"))
}

pub fn diff_string_finds_added_and_removed_lines_test() {
  let left = "line1\nline2\nline3"
  let right = "line1\nlineX\nline3"
  let d = diff.diff_string(left, right)
  let rendered = diff.render(d)
  should.be_true(string.contains(rendered, "  line1"))
  should.be_true(string.contains(rendered, "- line2"))
  should.be_true(string.contains(rendered, "+ lineX"))
  should.be_true(string.contains(rendered, "  line3"))
}

pub fn diff_string_equal_collapses_test() {
  let d = diff.diff_string("abc", "abc")
  case d {
    Same(_) -> Nil
    _ -> should.fail()
  }
}

pub fn segment_constructors_are_visible_test() {
  // Smoke test that the Segment public constructors are usable.
  let _ = Common("a")
  let _ = Removed("b")
  let _ = Added("c")
  Nil
}

pub fn tuple_diff_per_position_test() {
  let d = diff.diff(#(1, "two", 3), #(1, "two", 9))
  let rendered = diff.render(d)
  // Position 2 differs (3 vs 9).
  should.be_true(string.contains(rendered, "#.2"))
  should.be_true(string.contains(rendered, "- 3"))
  should.be_true(string.contains(rendered, "+ 9"))
}

pub fn tuple_diff_equal_collapses_test() {
  let d = diff.diff(#("a", 1), #("a", 1))
  case d {
    Same(_) -> Nil
    _ -> should.fail()
  }
}
