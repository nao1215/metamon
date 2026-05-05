//// Generators: deterministic, size-aware samplers that produce values
//// alongside their lazy shrink alternatives.
////
//// A `Generator(a)` is a pair of:
////   * `run`: takes a seed and a size and returns a `Tree(a)`
////   * `edges`: a finite list of must-try boundary values
////
//// Combinators (`map`, `bind`, `map2`, `tuple2`, `one_of`, ...) preserve
//// integrated shrinking via the underlying `Tree(a)` and propagate edges
//// in a way appropriate for each combinator (see § 4.4 of the spec).

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import metamon/generator/edges as edge_lib
import metamon/generator/range.{type Range}
import metamon/generator/seed.{type Seed} as seed_module
import metamon/generator/shrink as shrink_lib
import metamon/generator/tree.{type Tree, Tree}

const default_max_edges: Int = 16

/// A generator of `a`. Use the constructors in this module rather than
/// pattern-matching on the opaque structure.
pub opaque type Generator(a) {
  Generator(run: fn(Seed, Int) -> Tree(a), edges: List(a))
}

// ---------- public access ----------

/// Run the generator at the given seed and size. Used by the runner;
/// most user code should not call this directly.
pub fn generate(g: Generator(a), s: Seed, size: Int) -> Tree(a) {
  g.run(s, size)
}

/// Inspect the must-try edge values associated with a generator.
pub fn edges_of(g: Generator(a)) -> List(a) {
  g.edges
}

/// Pull `n` plain sample values, ignoring shrink trees. Useful at the
/// REPL or in test diagnostics.
pub fn sample(g: Generator(a), n: Int) -> List(a) {
  sample_loop(g, seed_module.seed(0), n, 50, [])
}

fn sample_loop(
  g: Generator(a),
  s: Seed,
  remaining: Int,
  size: Int,
  acc: List(a),
) -> List(a) {
  case remaining <= 0 {
    True -> list.reverse(acc)
    False -> {
      let #(left, right) = seed_module.split(s)
      let value = g.run(left, size).value
      sample_loop(g, right, remaining - 1, size, [value, ..acc])
    }
  }
}

/// Bucket `n` generated values via `classify` for distribution sanity
/// checks.
pub fn statistics(
  g: Generator(a),
  n: Int,
  classify: fn(a) -> String,
) -> Dict(String, Int) {
  sample(g, n)
  |> list.fold(dict.new(), fn(acc, value) {
    let label = classify(value)
    dict.upsert(acc, label, fn(existing) {
      case existing {
        Some(count) -> count + 1
        None -> 1
      }
    })
  })
}

// ---------- edge management ----------

/// Add a fixed list of must-try inputs that the runner will exercise
/// before random generation.
pub fn with_examples(g: Generator(a), examples: List(a)) -> Generator(a) {
  Generator(run: g.run, edges: list_append(g.edges, examples))
}

/// Append more edges to an existing generator. Symmetric to
/// `with_examples` but reads better for library authors.
pub fn add_edges(g: Generator(a), more: List(a)) -> Generator(a) {
  Generator(run: g.run, edges: list_append(g.edges, more))
}

/// Strip the edges from a generator. Useful when composing into a
/// product type that has its own edge story.
pub fn no_edges(g: Generator(a)) -> Generator(a) {
  Generator(run: g.run, edges: [])
}

// ---------- core combinators ----------

/// A constant generator that always returns `value` and has no shrinks.
pub fn return(value: a) -> Generator(a) {
  Generator(run: fn(_seed: Seed, _size: Int) { tree.singleton(value) }, edges: [
    value,
  ])
}

/// Functor map. Edges are mapped element-wise.
pub fn map(g: Generator(a), f: fn(a) -> b) -> Generator(b) {
  Generator(
    run: fn(s: Seed, size: Int) { tree.map(g.run(s, size), f) },
    edges: list.map(g.edges, f),
  )
}

/// Monadic bind. Edges are taken from the outer generator only (the
/// inner edges depend on the value, which is not safe to enumerate at
/// composition time without running the inner generator with a fixed
/// seed).
pub fn bind(g: Generator(a), k: fn(a) -> Generator(b)) -> Generator(b) {
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(s_outer, s_inner) = seed_module.split(s)
      let outer_tree = g.run(s_outer, size)
      tree.bind(outer_tree, fn(value) {
        let inner_gen = k(value)
        inner_gen.run(s_inner, size)
      })
    },
    edges: list.flat_map(g.edges, fn(a) { k(a).edges })
      |> take(default_max_edges),
  )
}

/// Applicative map over two independent generators. Shrinking holds one
/// component fixed while shrinking the other (via `tree.zip`).
pub fn map2(
  g1: Generator(a),
  g2: Generator(b),
  f: fn(a, b) -> c,
) -> Generator(c) {
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(s1, s2) = seed_module.split(s)
      let t = tree.zip(g1.run(s1, size), g2.run(s2, size))
      tree.map(t, fn(pair) { f(pair.0, pair.1) })
    },
    edges: cartesian_capped(g1.edges, g2.edges, f, default_max_edges),
  )
}

/// Three-way applicative map.
pub fn map3(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  f: fn(a, b, c) -> d,
) -> Generator(d) {
  map2(map2(g1, g2, fn(a, b) { #(a, b) }), g3, fn(pair, c) {
    f(pair.0, pair.1, c)
  })
}

/// Four-way applicative map.
pub fn map4(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  f: fn(a, b, c, d) -> e,
) -> Generator(e) {
  map2(map3(g1, g2, g3, fn(a, b, c) { #(a, b, c) }), g4, fn(triple, d) {
    f(triple.0, triple.1, triple.2, d)
  })
}

/// Five-way applicative map.
pub fn map5(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
  f: fn(a, b, c, d, e) -> g,
) -> Generator(g) {
  map2(map4(g1, g2, g3, g4, fn(a, b, c, d) { #(a, b, c, d) }), g5, fn(quad, e) {
    f(quad.0, quad.1, quad.2, quad.3, e)
  })
}

/// Six-way applicative map.
pub fn map6(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
  g6: Generator(g),
  f: fn(a, b, c, d, e, g) -> h,
) -> Generator(h) {
  map2(
    map5(g1, g2, g3, g4, g5, fn(a, b, c, d, e) { #(a, b, c, d, e) }),
    g6,
    fn(quint, x) { f(quint.0, quint.1, quint.2, quint.3, quint.4, x) },
  )
}

/// Pair two independent generators.
pub fn tuple2(g1: Generator(a), g2: Generator(b)) -> Generator(#(a, b)) {
  map2(g1, g2, fn(a, b) { #(a, b) })
}

/// Triple of independent generators.
pub fn tuple3(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
) -> Generator(#(a, b, c)) {
  map3(g1, g2, g3, fn(a, b, c) { #(a, b, c) })
}

/// Quadruple of independent generators.
pub fn tuple4(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
) -> Generator(#(a, b, c, d)) {
  map4(g1, g2, g3, g4, fn(a, b, c, d) { #(a, b, c, d) })
}

/// Quintuple of independent generators.
pub fn tuple5(
  g1: Generator(a),
  g2: Generator(b),
  g3: Generator(c),
  g4: Generator(d),
  g5: Generator(e),
) -> Generator(#(a, b, c, d, e)) {
  map5(g1, g2, g3, g4, g5, fn(a, b, c, d, e) { #(a, b, c, d, e) })
}

// ---------- choice and weighting ----------

/// Pick uniformly from a non-empty list of generators. Edges are the
/// concatenation of all branch edges.
pub fn one_of(generators: List(Generator(a))) -> Generator(a) {
  let assert [first, ..] = generators as "metamon.one_of: empty list"
  let count = list.length(generators)
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(idx, s_rest) = seed_module.next_int_in(s, 0, count - 1)
      let chosen = case list_at(generators, idx) {
        Some(g) -> g
        None -> first
      }
      chosen.run(s_rest, size)
    },
    edges: list.flat_map(generators, fn(g) { g.edges })
      |> take(default_max_edges),
  )
}

/// Weighted choice over a non-empty list of `(weight, generator)` pairs.
/// Weights must be positive integers; non-positive weights are treated
/// as `1`.
pub fn frequency(weighted: List(#(Int, Generator(a)))) -> Generator(a) {
  let assert [#(_, first), ..] = weighted as "metamon.frequency: empty list"
  let normalised =
    list.map(weighted, fn(pair) {
      case pair.0 < 1 {
        True -> #(1, pair.1)
        False -> pair
      }
    })
  let total = list.fold(normalised, 0, fn(acc, pair) { acc + pair.0 })
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(roll, s_rest) = seed_module.next_int_in(s, 0, total - 1)
      let chosen = pick_by_weight(normalised, roll, first)
      chosen.run(s_rest, size)
    },
    edges: list.flat_map(normalised, fn(pair) { pair.1.edges })
      |> take(default_max_edges),
  )
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

// ---------- sized / scaled / filter / recursive ----------

/// Construct a generator whose strategy depends on the current size.
pub fn sized(builder: fn(Int) -> Generator(a)) -> Generator(a) {
  Generator(
    run: fn(s: Seed, size: Int) {
      let inner = builder(size)
      inner.run(s, size)
    },
    edges: builder(0).edges,
  )
}

/// Override the size used by a generator.
pub fn resize(g: Generator(a), new_size: Int) -> Generator(a) {
  Generator(run: fn(s: Seed, _size: Int) { g.run(s, new_size) }, edges: g.edges)
}

/// Transform the size given to a generator.
pub fn scale(g: Generator(a), f: fn(Int) -> Int) -> Generator(a) {
  Generator(run: fn(s: Seed, size: Int) { g.run(s, f(size)) }, edges: g.edges)
}

/// Reject values that fail `predicate`. The implementation retries
/// internally up to `filter_retry_limit` times before panicking; this
/// is the canonical "filter is too strict" failure and is preferable
/// to silently misreporting the property.
///
/// Edges are filtered by `predicate` so user-supplied edges that fail
/// the predicate are silently dropped (they would never be tried
/// anyway).
pub fn filter(g: Generator(a), predicate: fn(a) -> Bool) -> Generator(a) {
  Generator(
    run: fn(s: Seed, size: Int) {
      filter_run(g, predicate, s, size, filter_retry_limit)
    },
    edges: list.filter(g.edges, predicate),
  )
}

const filter_retry_limit: Int = 100

fn filter_run(
  g: Generator(a),
  predicate: fn(a) -> Bool,
  s: Seed,
  size: Int,
  retries_left: Int,
) -> Tree(a) {
  let t = g.run(s, size)
  case predicate(t.value) {
    True -> tree.filter(t, predicate)
    False -> {
      case retries_left <= 0 {
        True ->
          panic as "metamon.filter: predicate rejected the configured number of candidates in a row; the predicate is too strict"
        False -> {
          let #(_, s2) = seed_module.split(s)
          filter_run(g, predicate, s2, size, retries_left - 1)
        }
      }
    }
  }
}

/// Recursive generator. At `size = 0` only `base` is used; at higher
/// sizes the recursive call is the result of `step` applied to a copy
/// of itself with halved size.
pub fn recursive(
  base: Generator(a),
  step: fn(Generator(a)) -> Generator(a),
) -> Generator(a) {
  sized(fn(size) {
    case size <= 0 {
      True -> base
      False -> {
        let smaller = recursive(base, step) |> resize(size / 2)
        step(smaller)
      }
    }
  })
}

// ---------- numeric ----------

/// Integer in the given range, with binary shrinking toward the range
/// origin. Standard edges (`0`, `1`, `-1`, bounds) are populated within
/// the constant interval.
pub fn int(range_value: Range) -> Generator(Int) {
  let origin = range.origin(range_value)
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(lo, hi) = range.bounds(range_value, size, 99)
      let #(value, _) = seed_module.next_int_in(s, lo, hi)
      let shrinks = shrink_lib.int_toward(origin, value)
      tree.unfold(value, fn(v) { shrink_lib.int_toward(origin, v) })
      |> attach_known_root(value, shrinks)
    },
    edges: edge_lib.ints_in(extreme_lo(range_value), extreme_hi(range_value)),
  )
}

fn extreme_lo(r: Range) -> Int {
  let #(lo, _) = range.bounds(r, 99, 99)
  lo
}

fn extreme_hi(r: Range) -> Int {
  let #(_, hi) = range.bounds(r, 99, 99)
  hi
}

// ---------- shortcut generators ----------

/// `True` or `False`, uniformly.
pub fn bool() -> Generator(Bool) {
  one_of([return(True), return(False)])
}

/// Integer in `[0, 1_000_000]`. Linear scaling so small values come
/// first; shrinks toward 0.
pub fn non_negative_int() -> Generator(Int) {
  int(range.linear(0, 1_000_000))
}

/// Integer in `[1, 1_000_000]`. Shrinks toward 1.
pub fn positive_int() -> Generator(Int) {
  int(range.linear_from(1, 1, 1_000_000))
}

/// Integer in `[-1_000_000, -1]`. Shrinks toward -1.
pub fn negative_int() -> Generator(Int) {
  int(range.linear_from(-1, -1_000_000, -1))
}

/// A single byte (`[0, 255]`).
pub fn byte() -> Generator(Int) {
  int(range.constant(0, 255))
}

/// Bit array of byte-length within `len`. Each byte is generated
/// uniformly.
pub fn bit_array(len: Range) -> Generator(BitArray) {
  list_of(byte(), len)
  |> map(bytes_to_bit_array)
}

fn bytes_to_bit_array(bytes: List(Int)) -> BitArray {
  list.fold(bytes, <<>>, fn(acc, b) { <<acc:bits, b:size(8)>> })
}

fn attach_known_root(
  unfolded: Tree(Int),
  expected_root: Int,
  _shrinks: List(Int),
) -> Tree(Int) {
  // unfold already produces the right shape; this hook exists so future
  // generators can override the root without recomputing the tree.
  case unfolded.value == expected_root {
    True -> unfolded
    False -> tree.singleton(expected_root)
  }
}

/// Float in the closed interval `[lo, hi]`. Shrinking moves toward the
/// closest endpoint (no fancy mantissa shrinking yet).
pub fn float(lo: Float, hi: Float) -> Generator(Float) {
  let #(low, high) = case lo >. hi {
    True -> #(hi, lo)
    False -> #(lo, hi)
  }
  Generator(
    run: fn(s: Seed, _size: Int) {
      let #(scaled, _) = seed_module.next_int_in(s, 0, 1_000_000)
      let fraction = int.to_float(scaled) /. 1_000_000.0
      let value = low +. { high -. low } *. fraction
      tree.from_list(value, [tree.singleton(low), tree.singleton(high)])
    },
    edges: edge_lib.floats_in(low, high),
  )
}

// ---------- string / codepoint ----------

/// A single ASCII lowercase letter generator (a-z).
pub fn ascii_lower() -> Generator(String) {
  let cp_gen = int(range.constant(97, 122))
  map(cp_gen, codepoint_to_string)
  |> override_edges(["a", "z", "m"])
}

/// A single ASCII uppercase letter generator (A-Z).
pub fn ascii_upper() -> Generator(String) {
  let cp_gen = int(range.constant(65, 90))
  map(cp_gen, codepoint_to_string)
  |> override_edges(["A", "Z", "M"])
}

/// A single ASCII letter generator (a-zA-Z).
pub fn ascii_letter() -> Generator(String) {
  one_of([ascii_lower(), ascii_upper()])
}

/// A single ASCII digit (0-9).
pub fn ascii_digit() -> Generator(String) {
  let cp_gen = int(range.constant(48, 57))
  map(cp_gen, codepoint_to_string)
  |> override_edges(["0", "9", "5"])
}

/// A single ASCII alphanumeric character.
pub fn ascii_alphanumeric() -> Generator(String) {
  one_of([ascii_letter(), ascii_digit()])
}

/// A single ASCII printable character (space..~).
pub fn ascii_printable() -> Generator(String) {
  let cp_gen = int(range.constant(32, 126))
  map(cp_gen, codepoint_to_string)
  |> override_edges([" ", "0", "A", "z", "~"])
}

/// A Unicode scalar value (excluding surrogates).
pub fn unicode_codepoint() -> Generator(Int) {
  one_of([int(range.constant(0, 0xD7FF)), int(range.constant(0xE000, 0x10FFFF))])
  |> override_edges([0, 32, 65, 0x4E00, 0x1F600])
}

/// A string built from `char_gen` characters with length in `len`.
pub fn string(char_gen: Generator(String), len: Range) -> Generator(String) {
  list_of(char_gen, len)
  |> map(string.concat)
  |> with_examples(["", " ", "\n"])
}

/// An ASCII string with length in `len`.
pub fn string_ascii(len: Range) -> Generator(String) {
  string(ascii_printable(), len)
  |> with_examples(edge_lib.strings_ascii())
}

/// A Unicode-aware string (includes BiDi/emoji/NUL via edges).
pub fn string_unicode(len: Range) -> Generator(String) {
  let cp_gen = unicode_codepoint() |> map(codepoint_int_to_string)
  string(cp_gen, len)
  |> with_examples(edge_lib.strings_unicode())
}

@external(erlang, "metamon_ffi", "codepoint_to_string")
@external(javascript, "../metamon_ffi.mjs", "codepoint_to_string")
fn codepoint_int_to_string(codepoint: Int) -> String

fn codepoint_to_string(codepoint: Int) -> String {
  codepoint_int_to_string(codepoint)
}

// ---------- collections ----------

/// A list of values whose length is drawn from `len`. Shrinking removes
/// elements via `shrink/list_drops` and shrinks each remaining element.
pub fn list_of(element: Generator(a), len: Range) -> Generator(List(a)) {
  Generator(
    run: fn(s: Seed, size: Int) {
      let #(s_len, s_items) = seed_module.split(s)
      let #(lo, hi) = range.bounds(len, size, 99)
      let #(length, _) = seed_module.next_int_in(s_len, lo, hi)
      generate_list_tree(element, s_items, size, length)
    },
    edges: list_edges(element.edges),
  )
}

fn generate_list_tree(
  element: Generator(a),
  s: Seed,
  size: Int,
  length: Int,
) -> Tree(List(a)) {
  case length <= 0 {
    True -> tree.singleton([])
    False -> {
      let #(s_head, s_tail) = seed_module.split(s)
      let head_tree = element.run(s_head, size)
      let tail_tree = generate_list_tree(element, s_tail, size, length - 1)
      let combined =
        tree.zip(head_tree, tail_tree)
        |> tree.map(fn(pair) { [pair.0, ..pair.1] })
      attach_drop_shrinks(combined)
    }
  }
}

fn attach_drop_shrinks(t: Tree(List(a))) -> Tree(List(a)) {
  let drops =
    shrink_lib.list_drops(t.value)
    |> list.map(tree.singleton)
  Tree(value: t.value, shrinks: prepend_to_shrinks(t.shrinks, drops))
}

fn prepend_to_shrinks(
  existing: tree.Shrinks(Tree(a)),
  prepended: List(Tree(a)),
) -> tree.Shrinks(Tree(a)) {
  tree.append_shrinks(tree.shrinks_from_list(prepended), existing)
}

fn list_edges(element_edges: List(a)) -> List(List(a)) {
  case element_edges {
    [] -> [[]]
    [first, ..] -> [[], [first], element_edges]
  }
}

/// Non-empty list. Wraps `list_of` and rejects empty lists from edges.
pub fn non_empty_list_of(
  element: Generator(a),
  len: Range,
) -> Generator(List(a)) {
  list_of(element, len)
  |> filter(fn(items) {
    case items {
      [] -> False
      _ -> True
    }
  })
}

/// Generate a `dict.Dict(k, v)` of size in `len`. Duplicate keys are
/// resolved by last-write-wins (the standard `dict.from_list`
/// semantics).
pub fn dict_of(
  key: Generator(k),
  value: Generator(v),
  len: Range,
) -> Generator(Dict(k, v)) {
  list_of(tuple2(key, value), len)
  |> map(dict.from_list)
}

/// Generate a `set.Set(a)` of size in `len`.
pub fn set_of(element: Generator(a), len: Range) -> Generator(Set(a)) {
  list_of(element, len)
  |> map(set.from_list)
}

/// `Some` / `None` of an inner generator.
pub fn option_of(g: Generator(a)) -> Generator(Option(a)) {
  frequency([
    #(1, return(None)),
    #(3, map(g, Some)),
  ])
  |> override_edges(option_edges(g.edges))
}

fn option_edges(inner_edges: List(a)) -> List(Option(a)) {
  case inner_edges {
    [] -> [None]
    [first, ..] -> [None, Some(first)]
  }
}

/// `Ok` / `Error` of two inner generators.
pub fn result_of(ok: Generator(a), err: Generator(e)) -> Generator(Result(a, e)) {
  frequency([
    #(3, map(ok, Ok)),
    #(1, map(err, Error)),
  ])
  |> override_edges(result_edges(ok.edges, err.edges))
}

fn result_edges(ok_edges: List(a), err_edges: List(e)) -> List(Result(a, e)) {
  let ok_part = case ok_edges {
    [] -> []
    [first, ..] -> [Ok(first)]
  }
  let err_part = case err_edges {
    [] -> []
    [first, ..] -> [Error(first)]
  }
  list_append(ok_part, err_part)
}

// ---------- internal helpers ----------

fn override_edges(g: Generator(a), new: List(a)) -> Generator(a) {
  Generator(run: g.run, edges: new)
}

fn cartesian_capped(
  left: List(a),
  right: List(b),
  combine: fn(a, b) -> c,
  cap: Int,
) -> List(c) {
  list.flat_map(left, fn(l) { list.map(right, fn(r) { combine(l, r) }) })
  |> take(cap)
}

fn take(items: List(a), n: Int) -> List(a) {
  case n, items {
    _, [] -> []
    n, _ if n <= 0 -> []
    n, [first, ..rest] -> [first, ..take(rest, n - 1)]
  }
}

fn list_at(items: List(a), index: Int) -> Option(a) {
  case items, index {
    [], _ -> None
    [first, ..], 0 -> Some(first)
    [_, ..rest], i -> list_at(rest, i - 1)
  }
}

fn list_append(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [first, ..rest] -> [first, ..list_append(rest, right)]
  }
}
