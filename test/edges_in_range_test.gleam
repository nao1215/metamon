//// Regression tests for #3: curated edge values must respect the
//// user-supplied length range. Before the fix, `string_ascii(range.constant(5, 8))`
//// emitted `""`, `" "`, and `"OAuth2Token"` (length 11) regardless of the
//// requested 5..8 window.

import gleam/list
import gleam/string
import gleeunit/should
import metamon/generator
import metamon/generator/range

pub fn string_ascii_edges_respect_length_range_test() {
  let g = generator.string_ascii(range.constant(5, 8))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 5 && length <= 8
    })
  should.be_true(all_in_range)
}

pub fn string_unicode_edges_respect_length_range_test() {
  let g = generator.string_unicode(range.constant(2, 4))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 2 && length <= 4
    })
  should.be_true(all_in_range)
}

pub fn string_edges_respect_length_range_test() {
  let g = generator.string(generator.ascii_lower(), range.constant(3, 5))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(s) {
      let length = string.length(s)
      length >= 3 && length <= 5
    })
  should.be_true(all_in_range)
}

pub fn list_of_edges_respect_length_range_test() {
  let g = generator.list_of(generator.byte(), range.constant(3, 5))
  let edges = generator.edges_of(g)
  let all_in_range =
    list.all(edges, fn(xs) {
      let length = list.length(xs)
      length >= 3 && length <= 5
    })
  should.be_true(all_in_range)
}
