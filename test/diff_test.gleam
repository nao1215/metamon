import gleam/string
import gleeunit/should
import metamon/internal/diff.{Differ, Same}

pub fn equal_values_collapse_to_same_test() {
  let d = inspected(42, 42)
  case d {
    Same(_) -> Nil
    _ -> should.fail()
  }
}

pub fn unequal_atoms_render_as_differ_test() {
  let d = inspected(1, 2)
  case d {
    Differ(left: l, right: r) -> {
      should.equal(l, "1")
      should.equal(r, "2")
    }
    _ -> should.fail()
  }
}

pub fn list_of_ints_diffs_per_index_test() {
  let d = inspected([1, 2, 3], [1, 9, 3])
  let rendered = diff.render(d)
  // Expect a difference at index 1 (`2` vs `9`).
  should.be_true(string.contains(rendered, "[#1]"))
  should.be_true(string.contains(rendered, "- 2"))
  should.be_true(string.contains(rendered, "+ 9"))
}

pub fn list_length_mismatch_shows_padding_test() {
  let d = inspected([1, 2], [1, 2, 3])
  let rendered = diff.render(d)
  should.be_true(string.contains(rendered, "+ 3"))
}

pub fn tuple_diff_per_position_test() {
  let d = inspected(#(1, "two", 3), #(1, "two", 9))
  let rendered = diff.render(d)
  // Position 2 differs (3 vs 9).
  should.be_true(string.contains(rendered, "#.2"))
  should.be_true(string.contains(rendered, "- 3"))
  should.be_true(string.contains(rendered, "+ 9"))
}

pub fn tuple_diff_equal_collapses_test() {
  let d = inspected(#("a", 1), #("a", 1))
  case d {
    Same(_) -> Nil
    _ -> should.fail()
  }
}

fn inspected(left: a, right: a) -> diff.Diff {
  diff.diff_inspected(string.inspect(left), string.inspect(right))
}
