import gleeunit/should
import metamon/internal/annotate

pub fn reset_clears_annotations_test() {
  annotate.reset()
  should.equal(annotate.current_annotations(), [])
}

pub fn annotations_keep_their_order_test() {
  annotate.reset()
  annotate.annotate("first", 1)
  annotate.annotate("second", 2)
  should.equal(annotate.current_annotations(), ["first: 1", "second: 2"])
}

pub fn annotate_renders_the_value_with_inspect_test() {
  annotate.reset()
  annotate.annotate("input", [1, 2, 3])
  should.equal(annotate.current_annotations(), ["input: [1, 2, 3]"])
}

pub fn reset_after_annotations_test() {
  annotate.annotate("x", "y")
  annotate.reset()
  should.equal(annotate.current_annotations(), [])
}
