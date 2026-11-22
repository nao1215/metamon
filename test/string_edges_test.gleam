//// String generators only use edges their character generator can
//// produce, inside the length range, without duplicates.

import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/generator

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

fn of(
  characters: generator.Characters,
) -> fn(generator.Range) -> generator.Generator(String) {
  fn(length) { generator.string(of: characters, length: length) }
}

type Case {
  Case(
    build: fn(generator.Range) -> generator.Generator(String),
    allowed: fn(String) -> Bool,
  )
}

fn cases() -> List(Case) {
  [
    Case(of(generator.Alphabetic), is_letter),
    Case(of(generator.Alphanumeric), is_alphanumeric),
    Case(of(generator.Digits), in_codepoints(_, 48, 57)),
    Case(of(generator.PrintableAscii), in_codepoints(_, 32, 126)),
    Case(of(generator.Ascii), in_codepoints(_, 0, 127)),
    Case(of(generator.Unicode), fn(_) { True }),
    Case(
      generator.string_from(generator.element_of(["a", "b", "c"]), _),
      in_codepoints(_, 97, 99),
    ),
  ]
}

pub fn string_edges_stay_inside_the_generator_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(generator.range(0, 12)),
      generator.int(generator.range(0, 12)),
    ),
    fn(bounds) {
      let #(lo, hi) = bounds
      assert list.all(cases(), fn(c) {
        let edges = generator.edges_of(c.build(generator.range(lo, hi)))
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
    generator.edges_of(generator.string(
      of: generator.PrintableAscii,
      length: generator.range(0, 3),
    ))
  assert !list.any(edges, string.contains(_, "\n"))
  assert list.unique(edges) == edges
}
