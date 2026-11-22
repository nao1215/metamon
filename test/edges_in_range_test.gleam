//// Regression tests for #3: curated edge values must respect the
//// user-supplied length range. Before the fix, `string_ascii(generator.range(5, 8))`
//// emitted `""`, `" "`, and `"OAuth2Token"` (length 11) regardless of the
//// requested 5..8 window.

import gleam/list
import gleam/string
import gleeunit/should
import metamon/generator

pub fn string_ascii_edges_respect_length_range_test() {
  let g = generator.string(of: generator.Ascii, length: generator.range(5, 8))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 5 && length <= 8
    })
  should.be_true(all_in_range)
}

pub fn string_unicode_edges_respect_length_range_test() {
  let g = generator.string(of: generator.Unicode, length: generator.range(2, 4))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 2 && length <= 4
    })
  should.be_true(all_in_range)
}

pub fn string_edges_respect_length_range_test() {
  let g = generator.string_from(lowercase(), generator.range(3, 5))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 3 && length <= 5
    })
  should.be_true(all_in_range)
}

pub fn list_of_edges_respect_length_range_test() {
  let g =
    generator.list_of(
      generator.int(generator.range(0, 255)),
      generator.range(3, 5),
    )
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(xs) {
      let length = list.length(xs)
      length >= 3 && length <= 5
    })
  should.be_true(all_in_range)
}

pub fn float_edges_keep_both_bounds_and_drop_outside_anchors_test() {
  // The anchors 0.0, 1.0 and -1.0 lie outside [10, 20]; both bounds are
  // kept because the interval is closed.
  generator.edges_of(generator.float(10.0, 20.0))
  |> should.equal([10.0, 20.0])
}

pub fn float_edges_are_deduplicated_test() {
  // lo and hi coincide with the anchors -1.0 and 1.0.
  generator.edges_of(generator.float(-1.0, 1.0))
  |> should.equal([-1.0, 1.0, 0.0])
}

pub fn int_edges_are_deduplicated_test() {
  // lo, hi, lo + 1 and hi - 1 coincide with the anchors 0, 1 and -1.
  generator.edges_of(generator.int(generator.range(-1, 1)))
  |> should.equal([0, 1, -1])
}

fn lowercase() -> generator.Generator(String) {
  generator.element_of(string.to_graphemes("abcdefghijklmnopqrstuvwxyz"))
}
