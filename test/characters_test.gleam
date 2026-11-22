//// Each `Characters` set produces exactly its characters, from random
//// values and from edge values, through `character`, `string` and
//// `string_from`.

import gleam/list
import gleam/string
import metamon/generator

fn code_point(character: String) -> Int {
  let assert [point] = string.to_utf_codepoints(character)
  string.utf_codepoint_to_int(point)
}

fn in_range(character: String, lo: Int, hi: Int) -> Bool {
  let point = code_point(character)
  point >= lo && point <= hi
}

fn is_letter(character: String) -> Bool {
  in_range(character, 65, 90) || in_range(character, 97, 122)
}

fn is_digit(character: String) -> Bool {
  in_range(character, 48, 57)
}

fn members(characters: generator.Characters) -> fn(String) -> Bool {
  case characters {
    generator.Ascii -> in_range(_, 0, 127)
    generator.PrintableAscii -> in_range(_, 32, 126)
    generator.Alphabetic -> is_letter
    generator.Alphanumeric -> fn(c) { is_letter(c) || is_digit(c) }
    generator.Digits -> is_digit
    generator.Unicode -> fn(c) {
      let point = code_point(c)
      point >= 0 && point <= 0x10FFFF && { point < 0xD800 || point > 0xDFFF }
    }
  }
}

const all: List(generator.Characters) = [
  generator.Ascii,
  generator.PrintableAscii,
  generator.Alphabetic,
  generator.Alphanumeric,
  generator.Digits,
  generator.Unicode,
]

pub fn character_stays_in_its_set_test() {
  list.each(all, fn(characters) {
    let g = generator.character(of: characters)
    let values =
      list.append(
        generator.sample(g, count: 300, seed: 7),
        generator.edges_of(g),
      )
    assert list.all(values, members(characters))
  })
}

pub fn string_stays_in_its_set_and_length_test() {
  list.each(all, fn(characters) {
    let g =
      generator.string(of: characters, length: generator.range(from: 2, to: 6))
    let values =
      list.append(
        generator.sample(g, count: 200, seed: 3),
        generator.edges_of(g),
      )
    assert list.all(values, fn(text) {
      let graphemes = string.to_utf_codepoints(text)
      let length = list.length(graphemes)
      length >= 2
      && length <= 6
      && list.all(graphemes, fn(point) {
        members(characters)(string.from_utf_codepoints([point]))
      })
    })
  })
}

pub fn sets_reach_their_bounds_test() {
  // A set that is too small would pass the membership checks above.
  let seen = fn(characters) {
    generator.sample(generator.character(of: characters), count: 2000, seed: 1)
    |> list.unique
  }
  assert list.length(seen(generator.Digits)) == 10
  assert list.length(seen(generator.Alphabetic)) == 52
  assert list.length(seen(generator.Alphanumeric)) == 62
  assert list.length(seen(generator.PrintableAscii)) == 95
  assert list.length(seen(generator.Ascii)) == 128
  assert list.any(seen(generator.Unicode), fn(c) { code_point(c) > 0xFFFF })
}

pub fn ascii_includes_control_characters_but_printable_does_not_test() {
  let control = fn(c) { code_point(c) < 32 || code_point(c) == 127 }
  let sampled = fn(characters) {
    generator.sample(generator.character(of: characters), count: 500, seed: 5)
  }
  assert list.any(sampled(generator.Ascii), control)
  assert !list.any(sampled(generator.PrintableAscii), control)
}

pub fn string_from_uses_the_given_characters_test() {
  let g =
    generator.string_from(
      characters: generator.element_of(["x", "-"]),
      length: generator.range(from: 0, to: 8),
    )
  let values =
    list.append(generator.sample(g, count: 200, seed: 9), generator.edges_of(g))
  assert list.all(values, fn(text) {
    string.length(text) <= 8
    && list.all(string.to_graphemes(text), fn(c) { c == "x" || c == "-" })
  })
}

pub fn unicode_string_edges_include_non_ascii_test() {
  let edges =
    generator.edges_of(generator.string(
      of: generator.Unicode,
      length: generator.range(from: 0, to: 20),
    ))
  assert list.contains(edges, "🦊")
  assert list.contains(edges, "")
}
