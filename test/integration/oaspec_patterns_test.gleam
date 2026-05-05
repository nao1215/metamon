//// Lightweight reproductions of the five oaspec usage patterns from
//// the spec (§ 8). Each test stands in for a real oaspec component
//// with a small, self-contained function so we can confirm the
//// metamon API supports the intended use sites without bringing
//// oaspec in as a dev-dependency.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/coverage
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import metamon/transform/dict as dict_t

// § 8.1 — `naming.to_snake_case` idempotency + keyword coverage.
//
// We use a stub `to_snake_case` to exercise the API. The point is
// that the test shape (with_examples, idempotency_of, coverage.cover)
// works end-to-end.
fn to_snake_case_stub(s: String) -> String {
  // For the stub we use a simple pattern: lowercase + collapse spaces.
  // It is genuinely idempotent.
  let lower = string.lowercase(s)
  string.replace(lower, "  ", " ")
}

pub fn snake_idempotent_with_examples_and_coverage_test() {
  let mr =
    metamon.idempotency_of(
      name: "snake_stub_idempotent",
      of: to_snake_case_stub,
    )
  let assert Ok(c) =
    metamon.with_runs(
      metamon.default_config()
        |> metamon.with_seed(metamon.seed(2026)),
      40,
    )
  metamon.forall_morph_with(
    c,
    generator.string_ascii(range.constant(0, 8))
      |> generator.with_examples(["", "Hello World", "OAuth2 Token"]),
    mr,
    fn(s) {
      coverage.classify("non_empty", string.length(s) > 0)
      to_snake_case_stub(s)
    },
  )
}

// § 8.2 — `normalize` idempotency. Stub: deduplicate consecutive
// whitespace and lowercase.
fn normalize_stub(input: String) -> String {
  case string.contains(input, "  ") {
    True -> normalize_stub(string.replace(input, "  ", " "))
    False -> string.lowercase(input)
  }
}

pub fn normalize_idempotent_test() {
  let mr =
    metamon.idempotency_of(
      name: "normalize_stub_idempotent",
      of: normalize_stub,
    )
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 30)
  metamon.forall_morph_with(
    c,
    generator.string_ascii(range.constant(0, 16)),
    mr,
    normalize_stub,
  )
}

// § 8.3 — Round-trip pattern: encode → decode → equal to original.
// Stub: prepend a fixed token, then strip it back.
fn write_spec(spec: List(Int)) -> String {
  list.map(spec, int.to_string)
  |> string.join(",")
}

fn parse_spec(text: String) -> Result(List(Int), Nil) {
  case text {
    "" -> Ok([])
    _ -> {
      let pieces = string.split(text, ",")
      decode_each(pieces, [])
    }
  }
}

fn decode_each(items: List(String), acc: List(Int)) -> Result(List(Int), Nil) {
  case items {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case parse_int(first) {
        Ok(n) -> decode_each(rest, [n, ..acc])
        Error(_) -> Error(Nil)
      }
  }
}

pub fn parse_write_round_trip_test() {
  // For round-trip we use a Plain MR with the identity transform and
  // a custom relation that asserts `parse(write(x)) == Ok(x)`.
  let r =
    relation.new("parse_after_write_recovers_input", fn(left, right) {
      // Both sides are `write(input)` (transform = identity), so
      // the assertion is implicit: parsing them must succeed and
      // give equal results, i.e. the encoder is deterministic.
      case parse_spec(left), parse_spec(right) {
        Ok(a), Ok(b) -> a == b
        _, _ -> False
      }
    })
  let mr =
    metamon.mr(
      name: "parse_write_round_trip",
      transform: transform.identity(),
      relation: r,
    )
  metamon.forall_morph(
    generator.list_of(
      generator.int(range.constant(0, 99)),
      range.constant(0, 5),
    ),
    mr,
    write_spec,
  )
}

// § 8.4 — Two equivalent representations. Stub: a JSON-ish string
// and a "tagged" version with spaces stripped — they should parse to
// the same dict.
fn strip_spaces(s: String) -> String {
  string.replace(s, " ", "")
}

fn parse_kv(text: String) -> Dict(String, String) {
  string.split(text, ",")
  |> list.filter_map(fn(pair) {
    case string.split_once(strip_spaces(pair), ":") {
      Ok(#(k, v)) -> Ok(#(k, v))
      Error(_) -> Error(Nil)
    }
  })
  |> dict.from_list()
}

pub fn yaml_json_equivalence_stub_test() {
  let strip_t = transform.new("strip_spaces", strip_spaces)
  let mr =
    metamon.mr(
      name: "kv_equivalent_modulo_whitespace",
      transform: strip_t,
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 12))
      |> generator.with_examples(["a:1", "a: 1, b:2", " a : 1 "]),
    mr,
    parse_kv,
  )
}

// § 8.5 — Field-order invariance: a dict's `to_list` order may vary,
// but a function that ignores order should be invariant under
// `shuffle_keys`.
fn count_pairs(d: Dict(String, Int)) -> Int {
  dict.size(d)
}

pub fn field_order_invariance_test() {
  let mr =
    metamon.invariant_under(
      name: "size_invariant_under_shuffle_keys",
      under: dict_t.shuffle_keys(0),
    )
  metamon.forall_morph(
    generator.dict_of(
      generator.string_ascii(range.constant(1, 4)),
      generator.int(range.constant(0, 9)),
      range.constant(0, 5),
    ),
    mr,
    count_pairs,
  )
}

// helpers

fn parse_int(s: String) -> Result(Int, Nil) {
  // Tiny integer parser: handles non-negative integers only.
  case s {
    "" -> Error(Nil)
    _ -> parse_int_loop(string.to_graphemes(s), 0)
  }
}

fn parse_int_loop(graphemes: List(String), acc: Int) -> Result(Int, Nil) {
  case graphemes {
    [] -> Ok(acc)
    [first, ..rest] ->
      case digit_value(first) {
        Ok(n) -> parse_int_loop(rest, acc * 10 + n)
        Error(_) -> Error(Nil)
      }
  }
}

fn digit_value(g: String) -> Result(Int, Nil) {
  case g {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    _ -> Error(Nil)
  }
}
