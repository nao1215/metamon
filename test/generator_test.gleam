import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleeunit/should
import metamon/generator
import metamon/generator/range
import metamon/generator/seed
import test_helpers

pub fn return_is_constant_test() {
  let g = generator.return(42)
  let t = generator.generate(g, seed.seed(0), 10)
  should.equal(t.value, 42)
}

pub fn map_transforms_value_and_edges_test() {
  let g = generator.return(5) |> generator.map(fn(n) { n * 2 })
  should.equal(generator.generate(g, seed.seed(0), 10).value, 10)
  should.equal(generator.edges_of(g), [10])
}

pub fn int_respects_range_bounds_test() {
  let g = generator.int(range.constant(10, 20))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    should.be_true(value >= 10 && value <= 20)
  })
}

pub fn int_edges_include_zero_when_in_range_test() {
  let g = generator.int(range.constant(-100, 100))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 0))
  should.be_true(list.contains(edges, -100))
  should.be_true(list.contains(edges, 100))
}

pub fn map2_combines_independent_generators_test() {
  let g =
    generator.map2(
      generator.int(range.constant(0, 9)),
      generator.int(range.constant(100, 199)),
      fn(a, b) { #(a, b) },
    )
  let t = generator.generate(g, seed.seed(7), 99)
  should.be_true(t.value.0 >= 0 && t.value.0 <= 9)
  should.be_true(t.value.1 >= 100 && t.value.1 <= 199)
}

pub fn tuple3_propagates_to_three_components_test() {
  let g =
    generator.tuple3(
      generator.return(1),
      generator.return("two"),
      generator.return(3.0),
    )
  let t = generator.generate(g, seed.seed(0), 0)
  should.equal(t.value, #(1, "two", 3.0))
}

pub fn one_of_picks_a_branch_test() {
  let g = generator.one_of([generator.return("a"), generator.return("b")])
  let observed =
    test_helpers.integers_from(0, 30)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0).value })
  should.be_true(list.contains(observed, "a"))
  should.be_true(list.contains(observed, "b"))
}

pub fn element_of_picks_a_value_test() {
  let g = generator.element_of(["red", "green", "blue"])
  let observed =
    test_helpers.integers_from(0, 90)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0).value })
  should.be_true(list.contains(observed, "red"))
  should.be_true(list.contains(observed, "green"))
  should.be_true(list.contains(observed, "blue"))
}

pub fn element_of_only_yields_listed_values_test() {
  let g = generator.element_of([1, 2, 3])
  test_helpers.integers_from(0, 50)
  |> list.each(fn(i) {
    let v = generator.generate(g, seed.seed(i), 0).value
    should.be_true(v == 1 || v == 2 || v == 3)
  })
}

pub fn element_of_singleton_is_constant_test() {
  let g = generator.element_of(["only"])
  test_helpers.integers_from(0, 10)
  |> list.each(fn(i) {
    should.equal(generator.generate(g, seed.seed(i), 0).value, "only")
  })
}

pub fn element_of_exposes_each_value_as_edge_test() {
  let g = generator.element_of(["html", "json", "png", "pdf"])
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, "html"))
  should.be_true(list.contains(edges, "json"))
  should.be_true(list.contains(edges, "png"))
  should.be_true(list.contains(edges, "pdf"))
}

pub fn frequency_respects_weights_test() {
  let g =
    generator.frequency([
      #(99, generator.return("hot")),
      #(1, generator.return("cold")),
    ])
  let observations =
    test_helpers.integers_from(0, 200)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0).value })
  let hot_count = list.filter(observations, fn(v) { v == "hot" }) |> list.length
  // Loose bound — random fluctuation, but heavily weighted should win.
  should.be_true(hot_count > 150)
}

pub fn list_of_within_length_bounds_test() {
  let g =
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(2, 5))
  test_helpers.integers_from(0, 20)
  |> list.each(fn(i) {
    let items = generator.generate(g, seed.seed(i), 99).value
    let len = list.length(items)
    should.be_true(len >= 2 && len <= 5)
  })
}

pub fn list_of_edges_include_empty_test() {
  let g = generator.list_of(generator.return(1), range.constant(0, 5))
  should.be_true(list.contains(generator.edges_of(g), []))
}

pub fn dict_of_produces_dict_test() {
  let g =
    generator.dict_of(
      generator.int(range.constant(0, 100)),
      generator.return("v"),
      range.constant(2, 4),
    )
  let value = generator.generate(g, seed.seed(0), 99).value
  should.be_true(dict.size(value) >= 1)
}

pub fn set_of_is_unique_test() {
  let g =
    generator.set_of(generator.int(range.constant(0, 9)), range.constant(3, 6))
  let value = generator.generate(g, seed.seed(0), 99).value
  // size <= length(input list)
  should.be_true(set.size(value) <= 6)
}

pub fn option_of_includes_none_in_edges_test() {
  let g = generator.option_of(generator.return(7))
  should.be_true(list.contains(generator.edges_of(g), None))
  should.be_true(list.contains(generator.edges_of(g), Some(7)))
}

pub fn result_of_includes_both_branches_in_edges_test() {
  let g = generator.result_of(generator.return("ok"), generator.return("err"))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, Ok("ok")))
  should.be_true(list.contains(edges, Error("err")))
}

pub fn with_examples_appends_edges_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3])
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 0))
  should.be_true(list.contains(edges, 1))
  should.be_true(list.contains(edges, 2))
  should.be_true(list.contains(edges, 3))
}

pub fn no_edges_drops_examples_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3])
    |> generator.no_edges()
  should.equal(generator.edges_of(g), [])
}

pub fn filter_drops_failing_edges_test() {
  let g =
    generator.return(0)
    |> generator.with_examples([1, 2, 3, 4])
    |> generator.filter(fn(n) { n > 2 })
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 3))
  should.be_true(list.contains(edges, 4))
  should.be_false(list.contains(edges, 1))
  should.be_false(list.contains(edges, 2))
}

pub fn sized_observes_size_test() {
  let g = generator.sized(fn(size) { generator.return(size) })
  let value_at_5 = generator.generate(g, seed.seed(0), 5).value
  let value_at_50 = generator.generate(g, seed.seed(0), 50).value
  should.equal(value_at_5, 5)
  should.equal(value_at_50, 50)
}

pub fn resize_overrides_size_test() {
  let g =
    generator.sized(fn(size) { generator.return(size) })
    |> generator.resize(7)
  should.equal(generator.generate(g, seed.seed(0), 99).value, 7)
}

pub fn ascii_lower_only_lowercase_test() {
  let g = generator.ascii_lower()
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 99).value
    let codepoints = string.to_utf_codepoints(value)
    let assert [single] = codepoints
    let cp = string.utf_codepoint_to_int(single)
    should.be_true(cp >= 97 && cp <= 122)
  })
}

pub fn string_ascii_within_length_bounds_test() {
  let g = generator.string_ascii(range.constant(3, 5))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 99).value
    let len = string.length(value)
    should.be_true(len >= 3 && len <= 5)
  })
}

pub fn string_ascii_codepoints_within_full_ascii_range_test() {
  let g = generator.string_ascii(range.constant(1, 8))
  // Every codepoint in every sample must lie in [0, 127]. Random
  // sampling now covers the full 7-bit window — control bytes
  // included — so the upper bound is what protects against accidental
  // leakage past ASCII.
  test_helpers.integers_from(0, 60)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 99).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(n >= 0 && n <= 127)
    })
  })
}

pub fn string_ascii_random_sampling_includes_control_bytes_test() {
  // Pin the new behaviour: with the sampler covering 0..127 (and a
  // generous sample budget), at least one control byte (< 32 or 127)
  // must show up. Previously this never happened — the bug closed
  // by this test was that random sampling skipped 33/128 of the
  // alphabet.
  let g = generator.string_ascii(range.constant(1, 8))
  let samples =
    test_helpers.integers_from(0, 200)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 50).value })
  let any_control =
    list.any(samples, fn(value) {
      string.to_utf_codepoints(value)
      |> list.any(fn(cp) {
        let n = string.utf_codepoint_to_int(cp)
        n < 32 || n == 127
      })
    })
  should.be_true(any_control)
}

pub fn string_alpha_only_letters_test() {
  let g = generator.string_alpha(range.constant(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true({ n >= 65 && n <= 90 } || { n >= 97 && n <= 122 })
    })
  })
}

pub fn string_alphanumeric_only_letters_or_digits_test() {
  let g = generator.string_alphanumeric(range.constant(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(
        { n >= 48 && n <= 57 }
        || { n >= 65 && n <= 90 }
        || { n >= 97 && n <= 122 },
      )
    })
  })
}

pub fn string_digit_only_digits_test() {
  let g = generator.string_digit(range.constant(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(n >= 48 && n <= 57)
    })
  })
}

pub fn string_printable_ascii_only_printable_test() {
  let g = generator.string_printable_ascii(range.constant(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(n >= 32 && n <= 126)
    })
  })
}

pub fn bit_array_printable_only_printable_bytes_test() {
  let g = generator.bit_array_printable(range.constant(1, 8))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    each_byte_in_bit_array(value, fn(b) { should.be_true(b >= 32 && b <= 126) })
  })
}

pub fn bit_array_utf8_decodes_back_to_string_test() {
  let g = generator.bit_array_utf8(range.constant(0, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50).value
    case bit_array.to_string(value) {
      Ok(_) -> Nil
      Error(_) -> should.fail()
    }
  })
}

fn each_byte_in_bit_array(bits: BitArray, check: fn(Int) -> Nil) -> Nil {
  case bits {
    <<>> -> Nil
    <<b:size(8), rest:bits>> -> {
      check(b)
      each_byte_in_bit_array(rest, check)
    }
    _ -> should.fail()
  }
}

pub fn statistics_buckets_values_test() {
  let g = generator.int(range.constant(0, 1))
  let buckets =
    generator.statistics(g, 100, fn(n) {
      case n == 0 {
        True -> "zero"
        False -> "one"
      }
    })
  let zero_count = case dict.get(buckets, "zero") {
    Ok(n) -> n
    Error(_) -> 0
  }
  let one_count = case dict.get(buckets, "one") {
    Ok(n) -> n
    Error(_) -> 0
  }
  should.equal(zero_count + one_count, 100)
}
