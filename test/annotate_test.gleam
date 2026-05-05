import gleeunit/should
import metamon/annotate

pub fn fresh_state_is_empty_test() {
  annotate.reset()
  should.equal(annotate.current_annotations(), [])
  should.equal(annotate.current_footnotes(), [])
}

pub fn annotate_pushes_message_test() {
  annotate.reset()
  annotate.annotate("first")
  annotate.annotate("second")
  should.equal(annotate.current_annotations(), ["first", "second"])
}

pub fn annotate_value_renders_via_inspect_test() {
  annotate.reset()
  annotate.annotate_value("input", [1, 2, 3])
  let assert [single] = annotate.current_annotations()
  should.equal(single, "input: [1, 2, 3]")
}

pub fn footnote_pushes_to_separate_buffer_test() {
  annotate.reset()
  annotate.annotate("body")
  annotate.footnote("at the bottom")
  should.equal(annotate.current_annotations(), ["body"])
  should.equal(annotate.current_footnotes(), ["at the bottom"])
}

pub fn reset_clears_both_buffers_test() {
  annotate.annotate("x")
  annotate.footnote("y")
  annotate.reset()
  should.equal(annotate.current_annotations(), [])
  should.equal(annotate.current_footnotes(), [])
}
