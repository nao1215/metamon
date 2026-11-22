import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/internal/seed
import test_helpers

pub fn return_is_constant_test() {
  let g = generator.return(42)
  let t = generator.generate(g, seed.seed(0), 10, 99)
  should.equal(t.value, 42)
}

pub fn map_transforms_value_and_edges_test() {
  let g = generator.return(5) |> generator.map(fn(n) { n * 2 })
  should.equal(generator.generate(g, seed.seed(0), 10, 99).value, 10)
  should.equal(generator.edges_of(g), [10])
}

pub fn int_respects_range_bounds_test() {
  let g = generator.int(generator.range(10, 20))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
    should.be_true(value >= 10 && value <= 20)
  })
}

pub fn int_edges_include_zero_when_in_range_test() {
  let g = generator.int(generator.range(-100, 100))
  let edges = generator.edges_of(g)
  should.be_true(list.contains(edges, 0))
  should.be_true(list.contains(edges, -100))
  should.be_true(list.contains(edges, 100))
}

pub fn map2_combines_independent_generators_test() {
  let g =
    generator.map2(
      generator.int(generator.range(0, 9)),
      generator.int(generator.range(100, 199)),
      fn(a, b) { #(a, b) },
    )
  let t = generator.generate(g, seed.seed(7), 99, 99)
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
  let t = generator.generate(g, seed.seed(0), 0, 99)
  should.equal(t.value, #(1, "two", 3.0))
}

pub fn one_of_picks_a_branch_test() {
  let g = generator.one_of([generator.return("a"), generator.return("b")])
  let observed =
    test_helpers.integers_from(0, 30)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0, 99).value })
  should.be_true(list.contains(observed, "a"))
  should.be_true(list.contains(observed, "b"))
}

pub fn element_of_picks_a_value_test() {
  let g = generator.element_of(["red", "green", "blue"])
  let observed =
    test_helpers.integers_from(0, 90)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0, 99).value })
  should.be_true(list.contains(observed, "red"))
  should.be_true(list.contains(observed, "green"))
  should.be_true(list.contains(observed, "blue"))
}

pub fn element_of_only_yields_listed_values_test() {
  let g = generator.element_of([1, 2, 3])
  test_helpers.integers_from(0, 50)
  |> list.each(fn(i) {
    let v = generator.generate(g, seed.seed(i), 0, 99).value
    should.be_true(v == 1 || v == 2 || v == 3)
  })
}

pub fn element_of_singleton_is_constant_test() {
  let g = generator.element_of(["only"])
  test_helpers.integers_from(0, 10)
  |> list.each(fn(i) {
    should.equal(generator.generate(g, seed.seed(i), 0, 99).value, "only")
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
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 0, 99).value })
  let hot_count = list.filter(observations, fn(v) { v == "hot" }) |> list.length
  // Loose bound — random fluctuation, but heavily weighted should win.
  should.be_true(hot_count > 150)
}

pub fn frequency_panics_on_zero_weight_test() {
  let #(panicked, message) =
    test_helpers.capture_panic(fn() {
      let _ =
        generator.frequency([
          #(0, generator.return("never_pick_me")),
          #(1, generator.return("always_pick_me")),
        ])
      Nil
    })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.frequency"))
  should.be_true(string.contains(message, "weight must be >= 1"))
  should.be_true(string.contains(message, "got 0"))
  should.be_true(string.contains(message, "position 0"))
}

pub fn frequency_panics_on_negative_weight_test() {
  let #(panicked, message) =
    test_helpers.capture_panic(fn() {
      let _ =
        generator.frequency([
          #(10, generator.return("a")),
          #(-5, generator.return("b")),
        ])
      Nil
    })
  should.be_true(panicked)
  should.be_true(string.contains(message, "metamon.frequency"))
  should.be_true(string.contains(message, "got -5"))
  should.be_true(string.contains(message, "position 1"))
}

// ---------- float_special ----------

pub fn float_special_edges_has_eight_values_test() {
  // NaN, +Inf, -Inf, 0.0, -0.0, 1.0, smallest_denormal, largest_finite.
  should.equal(list.length(generator.edges_of(generator.float_special())), 8)
}

pub fn float_special_edges_includes_finite_anchors_test() {
  // Easy structural check: 0.0 and 1.0 are the predictable anchors.
  let edges = generator.edges_of(generator.float_special())
  should.be_true(list.contains(edges, 0.0))
  should.be_true(list.contains(edges, 1.0))
}

pub fn float_special_edges_largest_is_max_double_test() {
  // 1.7976931348623157e308 is the largest finite IEEE 754 double.
  // Comparisons with NaN return False on both BEAM and JS (no
  // badarith), so the `>.` chain below ignores NaN entries even
  // without a NaN-aware filter.
  let edges = generator.edges_of(generator.float_special())
  let big = list.any(edges, fn(x) { x >. 1.0e300 })
  should.be_true(big)
}

pub fn float_special_edges_includes_negative_infinity_test() {
  let edges = generator.edges_of(generator.float_special())
  let neg_huge = list.any(edges, fn(x) { x <. -1.0e300 })
  should.be_true(neg_huge)
}

pub fn float_special_runs_through_metamon_test() {
  // Smoke: the runner must accept the special values and pass them
  // to the property without arithmetic intervention. The property
  // returns True for every input — this just verifies that no edge
  // value crashes the runner pipeline (e.g. via badarith on the BEAM).
  metamon.forall(generator.float_special(), fn(_x) { Nil })
}

// ---------- tuple6 ----------

pub fn tuple6_packs_six_components_test() {
  let g =
    generator.tuple6(
      generator.return(1),
      generator.return(2),
      generator.return(3),
      generator.return(4),
      generator.return(5),
      generator.return(6),
    )
  should.equal(generator.generate(g, seed.seed(0), 10, 99).value, #(
    1,
    2,
    3,
    4,
    5,
    6,
  ))
}

pub fn list_of_within_length_bounds_test() {
  let g =
    generator.list_of(
      generator.int(generator.range(0, 9)),
      generator.range(2, 5),
    )
  test_helpers.integers_from(0, 20)
  |> list.each(fn(i) {
    let items = generator.generate(g, seed.seed(i), 99, 99).value
    let len = list.length(items)
    should.be_true(len >= 2 && len <= 5)
  })
}

pub fn list_of_edges_include_empty_test() {
  let g = generator.list_of(generator.return(1), generator.range(0, 5))
  should.be_true(list.contains(generator.edges_of(g), []))
}

pub fn dict_of_produces_dict_test() {
  let g =
    generator.dict_of(
      generator.int(generator.range(0, 100)),
      generator.return("v"),
      generator.range(2, 4),
    )
  let value = generator.generate(g, seed.seed(0), 99, 99).value
  should.be_true(dict.size(value) >= 1)
}

pub fn set_of_is_unique_test() {
  let g =
    generator.set_of(
      generator.int(generator.range(0, 9)),
      generator.range(3, 6),
    )
  let value = generator.generate(g, seed.seed(0), 99, 99).value
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
  let value_at_5 = generator.generate(g, seed.seed(0), 5, 99).value
  let value_at_50 = generator.generate(g, seed.seed(0), 50, 99).value
  should.equal(value_at_5, 5)
  should.equal(value_at_50, 50)
}

pub fn string_ascii_within_length_bounds_test() {
  let g = generator.string(of: generator.Ascii, length: generator.range(3, 5))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 99, 99).value
    let len = string.length(value)
    should.be_true(len >= 3 && len <= 5)
  })
}

pub fn string_ascii_codepoints_within_full_ascii_range_test() {
  let g = generator.string(of: generator.Ascii, length: generator.range(1, 8))
  // Every codepoint in every sample must lie in [0, 127]. Random
  // sampling now covers the full 7-bit window — control bytes
  // included — so the upper bound is what protects against accidental
  // leakage past ASCII.
  test_helpers.integers_from(0, 60)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 99, 99).value
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
  let g = generator.string(of: generator.Ascii, length: generator.range(1, 8))
  let samples =
    test_helpers.integers_from(0, 200)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 50, 99).value })
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
  let g =
    generator.string(of: generator.Alphabetic, length: generator.range(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true({ n >= 65 && n <= 90 } || { n >= 97 && n <= 122 })
    })
  })
}

pub fn string_alphanumeric_only_letters_or_digits_test() {
  let g =
    generator.string(of: generator.Alphanumeric, length: generator.range(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
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
  let g = generator.string(of: generator.Digits, length: generator.range(1, 6))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(n >= 48 && n <= 57)
    })
  })
}

pub fn string_printable_ascii_only_printable_test() {
  let g =
    generator.string(
      of: generator.PrintableAscii,
      length: generator.range(1, 6),
    )
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
    string.to_utf_codepoints(value)
    |> list.each(fn(cp) {
      let n = string.utf_codepoint_to_int(cp)
      should.be_true(n >= 32 && n <= 126)
    })
  })
}

pub fn bit_array_unaligned_total_bits_within_range_test() {
  // Every sample's bit_size must lie inside the configured range.
  let g = generator.bit_array_unaligned(generator.range(0, 13))
  test_helpers.integers_from(0, 30)
  |> list.each(fn(i) {
    let value = generator.generate(g, seed.seed(i), 50, 99).value
    let bits = bit_array.bit_size(value)
    should.be_true(bits >= 0 && bits <= 13)
  })
}

pub fn bit_array_unaligned_can_produce_sub_byte_lengths_test() {
  // Sample widely; at least one value must have bit_size NOT divisible
  // by 8. Without sub-byte support every sample would be byte-aligned
  // and this assertion would fail — that's the property that pins the
  // new behaviour.
  let g = generator.bit_array_unaligned(generator.range(1, 23))
  let any_unaligned =
    test_helpers.integers_from(0, 60)
    |> list.map(fn(i) { generator.generate(g, seed.seed(i), 50, 99).value })
    |> list.any(fn(value) { bit_array.bit_size(value) % 8 != 0 })
  should.be_true(any_unaligned)
}

pub fn float_samples_stay_in_a_range_away_from_zero_test() {
  // An interval that does not start at 0 catches arithmetic that only
  // works when lo is 0.
  generator.sample(generator.float(10.0, 20.0), count: 200, seed: 0)
  |> list.all(fn(x) { x >=. 10.0 && x <=. 20.0 })
  |> should.be_true
}

// ---------- sample ----------

pub fn sample_is_deterministic_for_a_seed_test() {
  let g =
    generator.list_of(
      generator.int(generator.range(from: -1000, to: 1000)),
      length: generator.range(from: 0, to: 5),
    )
  should.equal(
    generator.sample(g, count: 50, seed: 42),
    generator.sample(g, count: 50, seed: 42),
  )
}

pub fn sample_differs_between_seeds_test() {
  let g = generator.int(generator.range(from: 0, to: 1_000_000))
  should.not_equal(
    generator.sample(g, count: 20, seed: 1),
    generator.sample(g, count: 20, seed: 2),
  )
}

pub fn sample_returns_count_values_test() {
  let g = generator.int(generator.range(from: 0, to: 9))
  should.equal(list.length(generator.sample(g, count: 17, seed: 0)), 17)
  should.equal(generator.sample(g, count: 0, seed: 0), [])
  should.equal(generator.sample(g, count: -3, seed: 0), [])
}

pub fn sample_grows_the_size_like_a_run_test() {
  // A linear range holds only its origin at size 0 and every value at
  // the largest size, so the first value is 0 and later ones spread out.
  let g = generator.int(generator.linear_range(from: 0, to: 1000))
  let assert [first, ..rest] = generator.sample(g, count: 100, seed: 3)
  should.equal(first, 0)
  should.be_true(list.any(rest, fn(n) { n > 500 }))
}
