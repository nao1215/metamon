//// Generators of random test inputs, with shrinking.
////
//// A `Generator(a)` produces values of type `a` from a seed and a size,
//// together with smaller alternatives the runner tries when a property
//// fails, and a short list of edge values the runner tries first. The
//// size grows from 0 on the first random input to `Config.max_size` on the
//// last.
////
//// ```gleam
//// let names =
////   generator.string(
////     of: generator.Alphabetic,
////     length: generator.range(from: 1, to: 12),
////   )
//// let ages = generator.int(generator.range(from: 0, to: 120))
//// let users = generator.map2(names, ages, with: User)
//// ```

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float as float_module
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import metamon/internal/edges as edge_lib
import metamon/internal/float_special
import metamon/internal/interval.{type Interval}
import metamon/internal/seed.{type Seed} as seed_module
import metamon/internal/shrink as shrink_lib
import metamon/internal/tree.{type Tree, Tree}

const default_max_edges: Int = 16

/// The largest size, as in the default `Config.max_size`.
const default_max_size: Int = 99

/// A generator of values of type `a`. Build one with the functions of
/// this module.
pub opaque type Generator(a) {
  // `run` takes the seed, the current size and the largest size of the
  // run, so ranges can scale to the configured `max_size`. Each edge value
  // carries its shrink tree, so a failing edge value shrinks too.
  Generator(run: fn(Seed, Int, Int) -> Tree(a), edges: List(Tree(a)))
}

/// An integer interval for `int`, and the lengths and sizes of the
/// collection generators. Build one with `range` or `linear_range`.
pub opaque type Range {
  Range(interval: Interval)
}

/// A set of characters for `character` and `string`.
pub type Characters {
  /// Every ASCII character, `U+0000` to `U+007F`, control characters
  /// included.
  Ascii
  /// The printable ASCII characters, from the space `U+0020` to `~`
  /// `U+007E`.
  PrintableAscii
  /// The ASCII letters `a`-`z` and `A`-`Z`.
  Alphabetic
  /// The ASCII letters and the digits `0`-`9`.
  Alphanumeric
  /// The digits `0`-`9`.
  Digits
  /// Every Unicode scalar value: `U+0000` to `U+10FFFF` without the
  /// surrogates `U+D800`-`U+DFFF`, which a Gleam `String` cannot hold.
  Unicode
}

// ---------- runner access ----------

/// Run the generator at the given seed, size and largest size. Used by
/// the runner.
@internal
pub fn generate(
  generator: Generator(a),
  seed: Seed,
  size: Int,
  max_size: Int,
) -> Tree(a) {
  generator.run(seed, size, max_size)
}

/// The edge values of a generator.
@internal
pub fn edges_of(generator: Generator(a)) -> List(a) {
  list.map(generator.edges, fn(edge) { edge.value })
}

/// The edge values of a generator with their shrink trees. Used by the
/// runner.
@internal
pub fn edge_trees(generator: Generator(a)) -> List(Tree(a)) {
  generator.edges
}

/// Return `count` values of `generator` drawn from `seed`, without
/// running a property. The same seed always gives the same values. The
/// size grows from 0 to 99 over the values like in a run, and the edge
/// values are not included. A `count` below 1 gives `[]`.
///
/// ```gleam
/// let digits = generator.int(generator.range(from: 0, to: 9))
/// generator.sample(digits, count: 3, seed: 42)
/// // -> three integers between 0 and 9
/// ```
pub fn sample(
  generator: Generator(a),
  count count: Int,
  seed seed: Int,
) -> List(a) {
  sample_loop(generator, seed_module.seed(seed), 0, count, [])
}

fn sample_loop(
  generator: Generator(a),
  seed: Seed,
  index: Int,
  count: Int,
  acc: List(a),
) -> List(a) {
  case index >= count {
    True -> list.reverse(acc)
    False -> {
      let #(here, rest) = seed_module.split(seed)
      let size = case count <= 1 {
        True -> default_max_size
        False -> index * default_max_size / { count - 1 }
      }
      let value = generator.run(here, size, default_max_size).value
      sample_loop(generator, rest, index + 1, count, [value, ..acc])
    }
  }
}

// ---------- ranges ----------

/// Return the range of integers between `from` and `to`, both included,
/// at every size. The bounds may come in either order. Values shrink
/// toward 0 when the range contains it, otherwise toward the lower bound.
pub fn range(from from: Int, to to: Int) -> Range {
  Range(interval.new(from, to, interval.Constant))
}

/// Return a range between `from` and `to` that grows with the size: at
/// size 0 it holds only its origin (0 when the range contains it,
/// otherwise the lower bound), and at the largest size it spans every
/// value. Early runs thus try small values first.
pub fn linear_range(from from: Int, to to: Int) -> Range {
  Range(interval.new(from, to, interval.Linear))
}

fn bounds(range: Range, size: Int, max_size: Int) -> #(Int, Int) {
  interval.bounds(range.interval, size, max_size)
}

/// The bounds at the largest size: every value the range can produce.
fn full_bounds(range: Range) -> #(Int, Int) {
  #(range.interval.lo, range.interval.hi)
}

// ---------- edge management ----------

/// Add `examples` to the edge values of `generator`, which the runner
/// tries before any random input. A failing example is reported as it is,
/// without shrinking; the built-in edge values shrink like random inputs.
pub fn with_examples(
  generator: Generator(a),
  examples: List(a),
) -> Generator(a) {
  Generator(
    run: generator.run,
    edges: list.append(generator.edges, list.map(examples, tree.singleton)),
  )
}

/// Remove the edge values of `generator`, so the runner starts with
/// random inputs.
pub fn no_edges(generator: Generator(a)) -> Generator(a) {
  Generator(run: generator.run, edges: [])
}

// ---------- core combinators ----------

/// Return a generator that always produces `value`. It does not shrink,
/// and `value` is its only edge value.
pub fn return(value: a) -> Generator(a) {
  Generator(
    run: fn(_seed: Seed, _size: Int, _max_size: Int) { tree.singleton(value) },
    edges: [tree.singleton(value)],
  )
}

/// Apply `function` to every value of `generator`, its shrinks and its
/// edge values.
pub fn map(generator: Generator(a), with function: fn(a) -> b) -> Generator(b) {
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      tree.map(generator.run(seed, size, max_size), function)
    },
    edges: list.map(generator.edges, tree.map(_, function)),
  )
}

/// Use each value of `generator` to choose the generator of the result.
/// Shrinking shrinks the first value, then the second. The edge values
/// are those of the generators chosen for the edge values of
/// `generator`, and they shrink within the chosen generator only.
pub fn bind(
  generator: Generator(a),
  with function: fn(a) -> Generator(b),
) -> Generator(b) {
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      let #(s_outer, s_inner) = seed_module.split(seed)
      let outer_tree = generator.run(s_outer, size, max_size)
      tree.bind(outer_tree, fn(value) {
        function(value).run(s_inner, size, max_size)
      })
    },
    edges: list.flat_map(generator.edges, fn(edge) {
      function(edge.value).edges
    })
      |> list.take(default_max_edges),
  )
}

/// Combine the values of two independent generators with `function`.
/// Shrinking shrinks one value while keeping the other; the edge values
/// are the combinations of their edge values, at most 16.
pub fn map2(
  g1: Generator(a),
  g2: Generator(b),
  with function: fn(a, b) -> c,
) -> Generator(c) {
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      let #(s1, s2) = seed_module.split(seed)
      let zipped =
        tree.zip(g1.run(s1, size, max_size), g2.run(s2, size, max_size))
      tree.map(zipped, fn(pair) { function(pair.0, pair.1) })
    },
    edges: cartesian_capped(
      g1.edges,
      g2.edges,
      fn(left, right) {
        tree.map(tree.zip(left, right), fn(pair) { function(pair.0, pair.1) })
      },
      default_max_edges,
    ),
  )
}

/// Combine three independent generators like `map2`.
pub fn map3(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  with function: fn(a, b, c) -> d,
) -> Generator(d) {
  map2(map2(g1, g2, with: fn(a, b) { #(a, b) }), g3, with: fn(pair, c) {
    function(pair.0, pair.1, c)
  })
}

/// Combine four independent generators like `map2`.
pub fn map4(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  with function: fn(a, b, c, d) -> e,
) -> Generator(e) {
  map2(
    map3(g1, g2, g3, with: fn(a, b, c) { #(a, b, c) }),
    g4,
    with: fn(triple, d) { function(triple.0, triple.1, triple.2, d) },
  )
}

/// Combine five independent generators like `map2`.
pub fn map5(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
  with function: fn(a, b, c, d, e) -> f,
) -> Generator(f) {
  map2(
    map4(g1, g2, g3, g4, with: fn(a, b, c, d) { #(a, b, c, d) }),
    g5,
    with: fn(quad, e) { function(quad.0, quad.1, quad.2, quad.3, e) },
  )
}

/// Combine six independent generators like `map2`. For more values,
/// nest the tuples, for example `map2(tuple3(..), tuple4(..), with: ..)`.
pub fn map6(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
  g6: Generator(f),
  with function: fn(a, b, c, d, e, f) -> g,
) -> Generator(g) {
  map2(
    map5(g1, g2, g3, g4, g5, with: fn(a, b, c, d, e) { #(a, b, c, d, e) }),
    g6,
    with: fn(quint, x) {
      function(quint.0, quint.1, quint.2, quint.3, quint.4, x)
    },
  )
}

/// Pair the values of two independent generators, shrinking like `map2`.
pub fn tuple2(g1: Generator(a), g2: Generator(b)) -> Generator(#(a, b)) {
  map2(g1, g2, with: fn(a, b) { #(a, b) })
}

/// Combine three independent generators into a tuple.
pub fn tuple3(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
) -> Generator(#(a, b, c)) {
  map3(g1, g2, g3, with: fn(a, b, c) { #(a, b, c) })
}

/// Combine four independent generators into a tuple.
pub fn tuple4(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
) -> Generator(#(a, b, c, d)) {
  map4(g1, g2, g3, g4, with: fn(a, b, c, d) { #(a, b, c, d) })
}

/// Combine five independent generators into a tuple.
pub fn tuple5(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
) -> Generator(#(a, b, c, d, e)) {
  map5(g1, g2, g3, g4, g5, with: fn(a, b, c, d, e) { #(a, b, c, d, e) })
}

/// Combine six independent generators into a tuple.
pub fn tuple6(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
  g6: Generator(f),
) -> Generator(#(a, b, c, d, e, f)) {
  map6(g1, g2, g3, g4, g5, g6, with: fn(a, b, c, d, e, f) {
    #(a, b, c, d, e, f)
  })
}

// ---------- choice and weighting ----------

/// Pick one of `generators` with equal chance for every value. The edge
/// values are those of all the generators, at most 16.
///
/// ## Panics
///
/// Panics when `generators` is empty.
pub fn one_of(generators: List(Generator(a))) -> Generator(a) {
  let assert [first, ..] = generators as "metamon.one_of: empty list"
  let count = list.length(generators)
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      let #(index, rest) = seed_module.next_int_in(seed, 0, count - 1)
      let chosen = case list.drop(generators, index) {
        [chosen, ..] -> chosen
        [] -> first
      }
      chosen.run(rest, size, max_size)
    },
    edges: list.flat_map(generators, fn(generator) { generator.edges })
      |> list.take(default_max_edges),
  )
}

/// Pick one of `values` with equal chance. Every value is an edge value.
///
/// ## Panics
///
/// Panics when `values` is empty.
pub fn element_of(values: List(a)) -> Generator(a) {
  let assert [_, ..] = values as "metamon.element_of: empty list"
  one_of(list.map(values, return))
}

/// Pick a generator with a chance proportional to its weight, so
/// `frequency([#(3, a), #(1, b)])` picks `a` three times as often as `b`.
///
/// ## Panics
///
/// Panics when `weighted` is empty or a weight is below 1.
pub fn frequency(weighted: List(#(Int, Generator(a)))) -> Generator(a) {
  let assert [#(_, first), ..] = weighted as "metamon.frequency: empty list"
  validate_weights(weighted, 0)
  let total = list.fold(weighted, 0, fn(acc, pair) { acc + pair.0 })
  Generator(
    run: fn(s: Seed, size: Int, max_size: Int) {
      let #(roll, s_rest) = seed_module.next_int_in(s, 0, total - 1)
      let chosen = pick_by_weight(weighted, roll, first)
      chosen.run(s_rest, size, max_size)
    },
    edges: list.flat_map(weighted, fn(pair) { pair.1.edges })
      |> list.take(default_max_edges),
  )
}

fn validate_weights(pairs: List(#(Int, Generator(a))), index: Int) -> Nil {
  case pairs {
    [] -> Nil
    [#(w, _), ..rest] ->
      case w < 1 {
        True ->
          panic as {
            "metamon.frequency: weight must be >= 1 (got "
            <> int.to_string(w)
            <> " at position "
            <> int.to_string(index)
            <> ")"
          }
        False -> validate_weights(rest, index + 1)
      }
  }
}

fn pick_by_weight(
  pairs: List(#(Int, Generator(a))),
  roll: Int,
  fallback: Generator(a),
) -> Generator(a) {
  case pairs {
    [] -> fallback
    [#(w, g), ..rest] ->
      case roll < w {
        True -> g
        False -> pick_by_weight(rest, roll - w, fallback)
      }
  }
}

// ---------- sized / filter / recursive ----------

/// Build the generator from the current size, which grows from 0 on the
/// first random input to `Config.max_size` on the last. The edge values
/// are those of the generator built for size 0.
pub fn sized(builder: fn(Int) -> Generator(a)) -> Generator(a) {
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      builder(size).run(seed, size, max_size)
    },
    edges: builder(0).edges,
  )
}

/// `generator` at a fixed size.
fn with_size(generator: Generator(a), size: Int) -> Generator(a) {
  Generator(
    run: fn(seed: Seed, _size: Int, max_size: Int) {
      generator.run(seed, size, max_size)
    },
    edges: generator.edges,
  )
}

/// Keep only the values of `generator` that satisfy `predicate`, retrying
/// with a new seed for each rejected value. Shrinks and edge values that
/// fail `predicate` are dropped too.
///
/// ## Panics
///
/// Panics when `predicate` rejects 100 values in a row: the predicate is
/// too strict for the generator, which should then produce the wanted
/// values directly.
pub fn filter(
  generator: Generator(a),
  keeping predicate: fn(a) -> Bool,
) -> Generator(a) {
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      filter_run(generator, predicate, seed, size, max_size, filter_retry_limit)
    },
    edges: generator.edges
      |> list.filter(fn(edge) { predicate(edge.value) })
      |> list.map(tree.filter(_, predicate)),
  )
}

const filter_retry_limit: Int = 100

fn filter_run(
  generator: Generator(a),
  predicate: fn(a) -> Bool,
  seed: Seed,
  size: Int,
  max_size: Int,
  retries_left: Int,
) -> Tree(a) {
  let candidate = generator.run(seed, size, max_size)
  case predicate(candidate.value) {
    True -> tree.filter(candidate, predicate)
    False -> {
      case retries_left <= 0 {
        True ->
          panic as "metamon.filter: predicate rejected the configured number of candidates in a row; the predicate is too strict"
        False -> {
          let #(_, next) = seed_module.split(seed)
          filter_run(
            generator,
            predicate,
            next,
            size,
            max_size,
            retries_left - 1,
          )
        }
      }
    }
  }
}

/// Build a recursive generator, such as one for trees. At size 0 it is
/// `base`; at a larger size it is `step` applied to the same generator at
/// half the size, so the values stay finite.
pub fn recursive(
  base: Generator(a),
  step: fn(Generator(a)) -> Generator(a),
) -> Generator(a) {
  sized(fn(size) {
    case size <= 0 {
      True -> base
      False -> step(recursive(base, step) |> with_size(size / 2))
    }
  })
}

// ---------- numbers and bits ----------

/// Return a generator of integers in `range`. Values shrink toward the
/// origin of the range. The edge values are 0, 1, -1, the bounds and
/// their neighbours, and the largest safe JavaScript integers, when they
/// lie in the range.
pub fn int(range: Range) -> Generator(Int) {
  let origin = range.interval.origin
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      let #(lo, hi) = bounds(range, size, max_size)
      let #(value, _) = seed_module.next_int_in(seed, lo, hi)
      int_tree(value, origin)
    },
    edges: {
      let #(lo, hi) = full_bounds(range)
      list.map(edge_lib.ints_in(lo, hi), int_tree(_, origin))
    },
  )
}

fn int_tree(value: Int, origin: Int) -> Tree(Int) {
  tree.unfold(value, shrink_lib.int_toward(origin, _))
}

/// Return a generator of `True` and `False` with equal chance. `True`
/// shrinks to `False`.
pub fn bool() -> Generator(Bool) {
  map(int(range(from: 0, to: 1)), with: fn(bit) { bit == 1 })
}

/// Return a generator of finite floats between `from` and `to`, both
/// included, in either order. Values shrink toward 0.0 when the range
/// contains it, otherwise toward the lower bound, and toward whole numbers
/// on the way. It never produces NaN or infinities; see `float_special`.
pub fn float(from from: Float, to to: Float) -> Generator(Float) {
  let #(low, high) = case from >. to {
    True -> #(to, from)
    False -> #(from, to)
  }
  let origin = case low <=. 0.0 && 0.0 <=. high {
    True -> 0.0
    False -> low
  }
  let float_tree = fn(value) {
    tree.unfold(value, shrink_lib.float_toward(origin, _, low, high))
  }
  Generator(
    run: fn(seed: Seed, _size: Int, _max_size: Int) {
      let #(steps, _) = seed_module.next_int_in(seed, 0, max_safe_integer)
      let fraction = int.to_float(steps) /. 9_007_199_254_740_992.0
      // Interpolating avoids `high - low`, which overflows for a range as
      // wide as the doubles.
      let value = low *. { 1.0 -. fraction } +. high *. fraction
      float_tree(float_module.clamp(value, min: low, max: high))
    },
    edges: list.map(edge_lib.floats_in(low, high), float_tree),
  )
}

/// 2^53 - 1: a float has 53 bits of precision.
const max_safe_integer: Int = 9_007_199_254_740_991

/// Return a generator of the IEEE 754 values `float` never produces: NaN,
/// positive and negative infinity, `0.0`, `-0.0`, `1.0`, the smallest
/// positive denormal and the largest finite double. Every value is also
/// an edge value.
///
/// On JavaScript the non-finite values are real NaN and infinities. On
/// Erlang, which cannot build them, NaN and positive infinity are the
/// largest finite double and negative infinity is its negation.
pub fn float_special() -> Generator(Float) {
  let edges = float_special_values()
  Generator(
    run: fn(seed: Seed, _size: Int, _max_size: Int) {
      let #(index, _) = seed_module.next_int_in(seed, 0, 7)
      let value = case list.drop(edges, index) {
        [value, ..] -> value
        [] -> 0.0
      }
      tree.singleton(value)
    },
    edges: list.map(edges, tree.singleton),
  )
}

fn float_special_values() -> List(Float) {
  [
    float_special.nan(),
    float_special.positive_infinity(),
    float_special.negative_infinity(),
    0.0,
    negative_zero(),
    1.0,
    float_special.smallest_positive_denormal(),
    float_special.largest_finite(),
  ]
}

fn negative_zero() -> Float {
  // -0.0 differs from 0.0 in its bit pattern on both targets; building it
  // by negation keeps the construction the same everywhere.
  0.0 *. -1.0
}

/// Return a generator of byte-aligned bit arrays whose length in bytes
/// lies in `bytes`. Every byte is uniform in 0-255.
pub fn bit_array(bytes length: Range) -> Generator(BitArray) {
  list_of(int(range(from: 0, to: 255)), length: length)
  |> map(with: pack_bytes)
}

/// Return a generator of bit arrays whose length in bits lies in `bits`,
/// so the length need not be a multiple of 8. Use it for code that must
/// handle or reject a trailing partial byte.
pub fn bit_array_unaligned(bits length: Range) -> Generator(BitArray) {
  list_of(int(range(from: 0, to: 1)), length: length)
  |> map(with: pack_single_bits)
}

fn pack_bytes(bytes: List(Int)) -> BitArray {
  list.map(bytes, fn(byte) { <<byte:size(8)>> })
  |> bit_array.concat
}

// Older gleam_stdlib releases allowed by gleam.toml only concatenate whole
// bytes on JavaScript, so single bits are appended with a bit-array
// segment instead of `bit_array.concat`.
fn pack_single_bits(bits: List(Int)) -> BitArray {
  list.fold(bits, <<>>, fn(acc, bit) { <<acc:bits, bit:size(1)>> })
}

// ---------- characters and strings ----------

/// Return a generator of one-character strings from `characters`. Values
/// shrink toward the lowest code point of the set.
pub fn character(of characters: Characters) -> Generator(String) {
  case characters {
    // NUL, tab, line feed, space, "0", "A", "z", "~" and DEL.
    Ascii -> code_points(0, 127, [0, 9, 10, 32, 48, 65, 122, 126, 127])
    PrintableAscii -> code_points(32, 126, [32, 48, 65, 122, 126])
    Alphabetic -> letters()
    Alphanumeric -> one_of([letters(), digits()])
    Digits -> digits()
    Unicode -> unicode_character()
  }
}

/// Every Unicode scalar value, drawn as an index into the scalar values
/// with the surrogates left out, so a value shrinks toward U+0000 and never
/// lands on a surrogate. Half of the values lie below the surrogates.
fn unicode_character() -> Generator(String) {
  let character_tree = fn(index) {
    int_tree(index, 0)
    |> tree.map(fn(index) {
      codepoint_int_to_string(case index < 0xD800 {
        True -> index
        False -> index + 0x800
      })
    })
  }
  Generator(
    run: fn(seed: Seed, _size: Int, _max_size: Int) {
      let #(half, rest) = seed_module.next_int_in(seed, 0, 1)
      let #(index, _) = case half {
        0 -> seed_module.next_int_in(rest, 0, 0xD7FF)
        _ -> seed_module.next_int_in(rest, 0xD800, 0x10F7FF)
      }
      character_tree(index)
    },
    // U+0000, space, "A", U+4E00 and U+1F600 (an emoji).
    edges: list.map([0, 32, 65, 0x4E00, 0x1F600 - 0x800], character_tree),
  )
}

/// Return a generator of strings of `characters` whose length in
/// characters lies in `length`. Shrinking removes characters, then
/// shrinks the remaining ones. The edge values include short strings
/// known to break parsers (`""`, `" "`, `"\n"`, keywords, an emoji for
/// `Unicode`) when they fit `length`.
///
/// ```gleam
/// generator.string(
///   of: generator.Alphanumeric,
///   length: generator.range(from: 1, to: 16),
/// )
/// ```
pub fn string(
  of characters: Characters,
  length length: Range,
) -> Generator(String) {
  let curated = case characters {
    Ascii -> edge_lib.strings_ascii()
    Unicode -> edge_lib.strings_unicode()
    PrintableAscii | Alphabetic | Alphanumeric | Digits -> []
  }
  string_with_edges(character(of: characters), length, curated)
}

/// Return a generator of strings built from the strings of `generator`,
/// with `length` of them. Use it for character sets outside
/// `Characters`, for example `element_of(["a", "b", "-"])`.
pub fn string_from(
  characters generator: Generator(String),
  length length: Range,
) -> Generator(String) {
  string_with_edges(generator, length, [])
}

fn letters() -> Generator(String) {
  one_of([
    code_points(97, 122, [97, 122, 109]),
    code_points(65, 90, [65, 90, 77]),
  ])
}

fn digits() -> Generator(String) {
  code_points(48, 57, [48, 57, 53])
}

/// One character with a code point in `[lo, hi]`, with the characters of
/// `edges` as its edge values.
fn code_points(lo: Int, hi: Int, edges: List(Int)) -> Generator(String) {
  let codes = int(range(from: lo, to: hi))
  let origin = range(from: lo, to: hi).interval.origin
  override_edges(codes, list.map(edges, int_tree(_, origin)))
  |> map(with: codepoint_int_to_string)
}

/// A string of `characters`, whose edges are the ones built from the
/// edges of `characters` plus the `curated` strings that fit the length
/// range, without duplicates. `curated` must only use characters that
/// `characters` can produce.
fn string_with_edges(
  characters: Generator(String),
  length: Range,
  curated: List(String),
) -> Generator(String) {
  let built = list_of(characters, length: length) |> map(with: string.concat)
  let #(lo, hi) = full_bounds(length)
  // A curated string shrinks by dropping characters, like a generated one.
  let fitting =
    curated
    |> list.filter(fn(text) {
      let count = string.length(text)
      count >= lo && count <= hi
    })
    |> list.map(fn(text) {
      list_tree(list.map(string.to_graphemes(text), tree.singleton), lo)
      |> tree.map(string.concat)
    })
  override_edges(built, unique_edges(list.append(built.edges, fitting)))
}

/// The edge trees without later trees whose value repeats an earlier one.
fn unique_edges(edges: List(Tree(a))) -> List(Tree(a)) {
  list.fold(edges, #([], []), fn(acc, edge) {
    let #(seen, kept) = acc
    case list.contains(seen, edge.value) {
      True -> acc
      False -> #([edge.value, ..seen], [edge, ..kept])
    }
  }).1
  |> list.reverse
}

@external(erlang, "metamon_ffi", "codepoint_to_string")
@external(javascript, "../metamon_ffi.mjs", "codepoint_to_string")
fn codepoint_int_to_string(codepoint: Int) -> String

// ---------- collections ----------

/// Return a generator of lists of values of `generator`, with a length
/// in `length`. Shrinking removes elements, largest blocks first and
/// never below the lower bound of `length`, then shrinks the remaining
/// elements. The edge values are `[]`, one edge element and all edge
/// elements, when their lengths fit.
pub fn list_of(
  generator: Generator(a),
  length length: Range,
) -> Generator(List(a)) {
  let #(min_length, max_length) = full_bounds(length)
  Generator(
    run: fn(seed: Seed, size: Int, max_size: Int) {
      let #(s_len, s_items) = seed_module.split(seed)
      let #(lo, hi) = bounds(length, size, max_size)
      let lo = int.max(lo, min_length)
      let #(count, _) = seed_module.next_int_in(s_len, lo, int.max(hi, lo))
      generate_element_trees(generator, s_items, size, max_size, count, [])
      |> list_tree(min_length)
    },
    edges: list_edges_in_range(generator.edges, min_length, max_length),
  )
}

fn generate_element_trees(
  element: Generator(a),
  s: Seed,
  size: Int,
  max_size: Int,
  remaining: Int,
  acc: List(Tree(a)),
) -> List(Tree(a)) {
  case remaining <= 0 {
    True -> list.reverse(acc)
    False -> {
      let #(s_head, s_tail) = seed_module.split(s)
      let head = element.run(s_head, size, max_size)
      generate_element_trees(element, s_tail, size, max_size, remaining - 1, [
        head,
        ..acc
      ])
    }
  }
}

/// The tree of a list built from its elements' trees. It shrinks by
/// dropping windows of elements (largest first, never below
/// `min_length`), then by shrinking one element at a time. Every
/// candidate is again a list tree, so shrinking continues from it.
///
/// Each candidate is built only when shrinking reaches it, and the
/// streams are joined pairwise so forcing them never nests deeper than
/// the log of the length.
fn list_tree(trees: List(Tree(a)), min_length: Int) -> Tree(List(a)) {
  let length = list.length(trees)
  let drops =
    drop_windows(length, min_length)
    |> list.map(fn(window) {
      let #(start, count) = window
      tree.lazy_shrinks(fn() {
        let kept =
          list.append(list.take(trees, start), list.drop(trees, start + count))
        [list_tree(kept, min_length)]
      })
    })
  let element_shrinks =
    list.index_map(trees, fn(element, index) {
      tree.map_shrinks(element.shrinks, fn(child) {
        let replaced =
          list.append(list.take(trees, index), [
            child,
            ..list.drop(trees, index + 1)
          ])
        list_tree(replaced, min_length)
      })
    })
  Tree(
    value: list.map(trees, fn(element) { element.value }),
    shrinks: concat_shrinks(list.append(drops, element_shrinks)),
  )
}

/// `(start, count)` windows to drop, in the order they are tried: the
/// whole list, then halves, quarters and so on, each size from the end
/// of the list towards the start.
fn drop_windows(length: Int, min_length: Int) -> List(#(Int, Int)) {
  drop_windows_loop(length, length, length - min_length, [])
  |> list.reverse
}

fn drop_windows_loop(
  length: Int,
  window: Int,
  max_drop: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case window <= 0 {
    True -> acc
    False -> {
      let acc = case window <= max_drop {
        True -> window_starts(length - window, window, acc)
        False -> acc
      }
      drop_windows_loop(length, window / 2, max_drop, acc)
    }
  }
}

fn window_starts(
  start: Int,
  window: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case start < 0 {
    True -> acc
    False -> window_starts(start - window, window, [#(start, window), ..acc])
  }
}

fn concat_shrinks(streams: List(tree.Shrinks(b))) -> tree.Shrinks(b) {
  case streams {
    [] -> tree.no_shrinks()
    [only] -> only
    _ -> concat_shrinks(pair_up(streams, []))
  }
}

fn pair_up(
  streams: List(tree.Shrinks(b)),
  acc: List(tree.Shrinks(b)),
) -> List(tree.Shrinks(b)) {
  case streams {
    [left, right, ..rest] ->
      pair_up(rest, [tree.append_shrinks(left, right), ..acc])
    [last] -> list.reverse([last, ..acc])
    [] -> list.reverse(acc)
  }
}

fn list_edges_in_range(
  element_edges: List(Tree(a)),
  lo_len: Int,
  hi_len: Int,
) -> List(Tree(List(a))) {
  let candidates = case element_edges {
    [] -> [[]]
    [first, ..] -> [[], [first], element_edges]
  }
  candidates
  |> list.filter(fn(trees) {
    let length = list.length(trees)
    length >= lo_len && length <= hi_len
  })
  |> list.map(list_tree(_, lo_len))
}

/// Return a generator of dicts with keys from `keys` and values from
/// `values`, built from a list of entries whose length lies in `size`.
/// A repeated key keeps its last value, so a dict can be smaller than
/// the lower bound of `size`.
pub fn dict_of(
  keys: Generator(k),
  values: Generator(v),
  size size: Range,
) -> Generator(Dict(k, v)) {
  list_of(tuple2(keys, values), length: size)
  |> map(with: dict.from_list)
}

/// Return a generator of sets of values of `generator`, built from a list
/// whose length lies in `size`. Repeated values collapse, so a set can be
/// smaller than the lower bound of `size`.
pub fn set_of(generator: Generator(a), size size: Range) -> Generator(Set(a)) {
  list_of(generator, length: size)
  |> map(with: set.from_list)
}

/// Return a generator of `None` and of `Some` with the values of
/// `generator`, `Some` three times as often. `Some` shrinks to `None`
/// first, then shrinks its value.
pub fn option_of(generator: Generator(a)) -> Generator(Option(a)) {
  let somes =
    Generator(
      run: fn(seed: Seed, size: Int, max_size: Int) {
        some_tree(generator.run(seed, size, max_size))
      },
      edges: list.map(generator.edges, some_tree),
    )
  frequency([#(1, return(None)), #(3, somes)])
  |> override_edges(case somes.edges {
    [] -> [tree.singleton(None)]
    [first, ..] -> [tree.singleton(None), first]
  })
}

fn some_tree(inner: Tree(a)) -> Tree(Option(a)) {
  Tree(
    value: Some(inner.value),
    shrinks: tree.append_shrinks(
      tree.lazy_shrinks(fn() { [tree.singleton(None)] }),
      tree.map_shrinks(inner.shrinks, some_tree),
    ),
  )
}

/// Return a generator of `Ok` with the values of `ok` and of `Error` with
/// the values of `error`, `Ok` three times as often.
pub fn result_of(
  ok: Generator(a),
  error: Generator(e),
) -> Generator(Result(a, e)) {
  frequency([
    #(3, map(ok, with: Ok)),
    #(1, map(error, with: Error)),
  ])
  |> override_edges(result_edges(ok.edges, error.edges))
}

fn result_edges(
  ok_edges: List(Tree(a)),
  err_edges: List(Tree(e)),
) -> List(Tree(Result(a, e))) {
  let ok_part = case ok_edges {
    [] -> []
    [first, ..] -> [tree.map(first, Ok)]
  }
  let err_part = case err_edges {
    [] -> []
    [first, ..] -> [tree.map(first, Error)]
  }
  list.append(ok_part, err_part)
}

// ---------- internal helpers ----------

fn override_edges(generator: Generator(a), new: List(Tree(a))) -> Generator(a) {
  Generator(run: generator.run, edges: new)
}

fn cartesian_capped(
  left: List(a),
  right: List(b),
  combine: fn(a, b) -> c,
  cap: Int,
) -> List(c) {
  list.flat_map(left, fn(l) { list.map(right, fn(r) { combine(l, r) }) })
  |> list.take(cap)
}
