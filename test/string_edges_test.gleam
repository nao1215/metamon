//// String generators only use edges their character generator can
//// produce, inside the length range, without duplicates.

import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

fn in_codepoints(s: String, lo: Int, hi: Int) -> Bool {
  string.to_utf_codepoints(s)
  |> list.all(fn(cp) {
    let n = string.utf_codepoint_to_int(cp)
    n >= lo && n <= hi
  })
}

fn is_letter(s: String) -> Bool {
  string.to_graphemes(s)
  |> list.all(fn(c) { in_codepoints(c, 65, 90) || in_codepoints(c, 97, 122) })
}

fn is_alphanumeric(s: String) -> Bool {
  string.to_graphemes(s)
  |> list.all(fn(c) { is_letter(c) || in_codepoints(c, 48, 57) })
}

type Case {
  Case(
    build: fn(range.Range) -> generator.Generator(String),
    allowed: fn(String) -> Bool,
  )
}

fn cases() -> List(Case) {
  [
    Case(generator.string_alpha, is_letter),
    Case(generator.string_alphanumeric, is_alphanumeric),
    Case(generator.string_digit, in_codepoints(_, 48, 57)),
    Case(generator.string_printable_ascii, in_codepoints(_, 32, 126)),
    Case(generator.string_ascii, in_codepoints(_, 0, 127)),
    Case(generator.string(generator.ascii_lower(), _), in_codepoints(_, 97, 122)),
  ]
}

pub fn string_edges_stay_inside_the_generator_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(0, 12)),
      generator.int(range.constant(0, 12)),
    ),
    fn(bounds) {
      let #(lo, hi) = bounds
      assert list.all(cases(), fn(c) {
        let edges = generator.edges_of(c.build(range.constant(lo, hi)))
        let #(lo, hi) = #(int.min(lo, hi), int.max(lo, hi))
        list.all(edges, fn(edge) {
          let length = string.length(edge)
          c.allowed(edge) && length >= lo && length <= hi
        })
        && list.unique(edges) == edges
      })
    },
  )
}

pub fn printable_ascii_edges_have_no_control_characters_test() {
  let edges =
    generator.edges_of(generator.string_printable_ascii(range.constant(0, 3)))
  assert !list.any(edges, string.contains(_, "\n"))
  assert list.unique(edges) == edges
}
