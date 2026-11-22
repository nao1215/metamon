# metamon

[![CI](https://github.com/nao1215/metamon/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/metamon/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/metamon/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/metamon/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/metamon)](https://hex.pm/packages/metamon)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/metamon/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/metamon)](https://hex.pm/packages/metamon)
[![License](https://img.shields.io/github/license/nao1215/metamon)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/metamon/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/metamon)

Property-based testing and metamorphic testing for Gleam. A property states a predicate over one input; a metamorphic relation states how the outputs for two related inputs (such as `f(x)` and `f(reverse(x))`) must relate. metamon generates inputs, shrinks failures and prints a report with a reproducible seed.

Each snippet below is mirrored in [`test/readme_test.gleam`](test/readme_test.gleam), so `gleam test` checks it on every CI run.

## Install

```sh
gleam add metamon --dev
```

Requires Gleam 1.14+, Erlang/OTP 27+ and Node.js 22+. See [Compatibility](#compatibility).

## Quick start

`string.trim` is idempotent: applying it twice gives the same result as applying it once. metamon has a template for that relation.

```gleam
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

pub fn trim_idempotent_test() {
  let mr = metamon.idempotency_of(name: "trim_idempotent", of: string.trim)
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 16)),
    mr,
    string.trim,
  )
}
```

When a relation breaks, the test panics with a named report. This is the report for `fn(s) { string.drop_start(s, 1) }`, which is not idempotent, run through the same test:

```
× metamorphic relation `drop_first_idempotent` failed
  test:        forall_morph
  source:      edge(2)
  config seed: 3287652029
  runs:        2 / 100
  shrinks:     0

  transform:   `apply drop_first_idempotent`
  relation:    `equal`

  source input  (shrunk):
    "\u{0000}\t\n 0Az~\u{007F}"

  follow-up input  (= transform(source)):
    "\t\n 0Az~\u{007F}"

  source output:
    "\t\n 0Az~\u{007F}"

  follow-up output:
    "\n 0Az~\u{007F}"

  diff (source_output vs follow-up_output):
    - "\t\n 0Az~\u{007F}"
    + "\n 0Az~\u{007F}"

  reproduce (paste into a test):
    // The MR failed for this input. To pin it as a regression,
    // call assert_morph with the shrunk input and the same MR.
    let input = "\u{0000}\t\n 0Az~\u{007F}"
    metamon.assert_morph(input, mr, f)
```

## Property-based testing

### `forall`

`metamon.forall` runs a one-argument predicate against many generated inputs:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import gleam/list

pub fn reverse_twice_is_identity_test() {
  metamon.forall(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 5),
    ),
    fn(xs) { list.reverse(list.reverse(xs)) == xs },
  )
}
```

### `forall_observable`

`forall_observable` lets the predicate return `#(observation, holds)`. The failure report then shows the observation under `predicate value`, next to the shrunk input:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import gleam/string

pub fn parse_round_trip_test() {
  metamon.forall_observable(
    generator.string_ascii(range.constant(0, 8)),
    fn(s) {
      let trimmed = string.trim(s)
      // `trimmed` is what the property body cares about, so expose it.
      #(trimmed, string.length(trimmed) <= string.length(s))
    },
  )
}
```

It saves one `annotate.annotate_value("predicate value", trimmed)` call.

## Metamorphic relations

A metamorphic relation says that transforming the input in a known way changes the output in a known way, or not at all. metamon has templates for the common shapes.

### Idempotency: `f(f(x)) == f(x)`

```gleam
import metamon
import metamon/generator
import metamon/generator/range

pub fn sort_dedupe_idempotent_test() {
  let mr =
    metamon.idempotency_of(name: "sort_dedupe_idempotent", of: sort_dedupe)
  metamon.forall_morph(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 6),
    ),
    mr,
    sort_dedupe,
  )
}
```

### Round-trip: `decode(encode(x)) == Ok(x)`

`forall_round_trip` checks an encoder and decoder pair. The report header is `round_trip[<name>]`.

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import gleam/int

pub fn int_string_round_trip_test() {
  metamon.forall_round_trip(
    gen: generator.int(range.constant(-1000, 1000)),
    name: "int_string_round_trip",
    encode: int.to_string,
    decode: int.parse,
  )
}
```

A round trip compares the decoded output with the source input, which the two-point shape of an `Mr` cannot express, so `forall_round_trip` is built on `forall` instead.

### Invariance: `f(T(x)) == f(x)`

`list.length` is unchanged by `reverse`:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/transform/list as list_t
import gleam/list

pub fn length_invariant_under_reverse_test() {
  let mr =
    metamon.invariant_under(
      name: "length_invariant_under_reverse",
      under: list_t.reverse(),
    )
  metamon.forall_morph(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 8),
    ),
    mr,
    list.length,
  )
}
```

### Equivariance: `U(f(x)) == f(T(x))`

The output transforms in a known way. `map(g)` commutes with `reverse`:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform/list as list_t
import gleam/list

pub fn map_commutes_with_reverse_test() {
  let mr =
    metamon.equivariant_under(
      name: "map_commutes_with_reverse",
      input: list_t.reverse(),
      output: list_t.reverse(),
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 6),
    ),
    mr,
    fn(xs) { list.map(xs, fn(n) { n * 2 }) },
  )
}
```

### Manual MR construction

When no template fits, build the MR from a `Transform(a)` and a `Relation(b)`:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform/list as list_t
import gleam/list

pub fn sum_invariant_under_append_zero_test() {
  let append_zero = list_t.append(0)
  let mr =
    metamon.mr(
      name: "sum_invariant_under_append_zero",
      transform: append_zero,
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 5),
    ),
    mr,
    fn(items) { list.fold(items, 0, fn(acc, n) { acc + n }) },
  )
}
```

### `assert_morph`

Checks one fixed input, for regression tests of a known failing case:

```gleam
import metamon
import metamon/transform/list as list_t

pub fn sum_reverse_regression_test() {
  let mr =
    metamon.invariant_under(
      name: "sum_invariant_under_reverse",
      under: list_t.reverse(),
    )
  metamon.assert_morph([1, 2, 3, 4, 5], mr, list_sum)
}
```

### Commutativity: `op(a, b) == op(b, a)`

`commutativity_of` builds an MR over the pair `#(a, a)` whose transform swaps the two components:

```gleam
import metamon
import metamon/generator
import metamon/generator/range

fn add(a: Int, b: Int) -> Int {
  a + b
}

pub fn add_commutative_test() {
  let mr = metamon.commutativity_of(name: "add_commutative")
  metamon.forall_morph(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    mr,
    fn(pair) { add(pair.0, pair.1) },
  )
}
```

### `forall_morphs`

Runs several MRs against the same `f` and reports every failure, not only the first:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/transform/list as list_t

pub fn sum_multi_mr_test() {
  let invariant_under_reverse =
    metamon.invariant_under(name: "sum_under_reverse", under: list_t.reverse())
  let invariant_under_append_zero =
    metamon.invariant_under(
      name: "sum_under_append_zero",
      under: list_t.append(0),
    )
  metamon.forall_morphs(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 4),
    ),
    [invariant_under_reverse, invariant_under_append_zero],
    list_sum,
  )
}
```

## Round-trip variants

`forall_round_trip` needs `encode: a -> b` and `decode: b -> Result(a, _)` and compares with `==`. Two variants cover codecs that do not fit.

### `forall_round_trip_partial`

For an encoder that returns `Result(b, _)`. Inputs it rejects are skipped, not counted as failures, which suits codecs with preconditions such as byte alignment or a version range.

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import gleam/int

pub fn readme_round_trip_partial_test() {
  // Stand-in for a real partial encoder: only encodes even integers.
  metamon.forall_round_trip_partial(
    gen: generator.int(range.constant(-50, 50)),
    name: "even_only_round_trip",
    encode: fn(n) {
      case n % 2 == 0 {
        True -> Ok(int.to_string(n))
        False -> Error(Nil)
      }
    },
    decode: fn(s) { int.parse(s) },
  )
}
```

### `forall_round_trip_under`

Compares with a `Relation(a)` instead of `==`, for decoded forms that normalise (a MIME type whose essence lowercases, for example). `relation.equivalent_under(via, name)` compares on a projection.

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import gleam/string

pub fn readme_round_trip_under_test() {
  let case_insensitive =
    relation.equivalent_under(string.lowercase, "case_insensitive")
  metamon.forall_round_trip_under(
    gen: generator.string_alpha(range.constant(0, 8)),
    name: "case_insensitive_round_trip",
    encode: string.lowercase,
    decode: fn(s) { Ok(s) },
    equality: case_insensitive,
  )
}
```

## Generators

### Common shortcuts

```gleam
import metamon/generator
import metamon/generator/range

pub fn shortcut_examples() {
  let _: generator.Generator(Bool)      = generator.bool()
  let _: generator.Generator(Int)       = generator.non_negative_int()
  let _: generator.Generator(Int)       = generator.positive_int()
  let _: generator.Generator(Int)       = generator.negative_int()
  let _: generator.Generator(Int)       = generator.byte()
  let _: generator.Generator(BitArray)  = generator.bit_array(range.constant(0, 16))
  let _: generator.Generator(BitArray)  = generator.bit_array_printable(range.constant(0, 16))
  let _: generator.Generator(BitArray)  = generator.bit_array_utf8(range.constant(0, 8))
  let _: generator.Generator(String)    = generator.string_alpha(range.constant(1, 8))
  let _: generator.Generator(String)    = generator.string_alphanumeric(range.constant(1, 8))
  let _: generator.Generator(String)    = generator.string_digit(range.constant(1, 4))
  let _: generator.Generator(String)    = generator.string_printable_ascii(range.constant(0, 16))
  Nil
}
```

These wrap `generator.int(range.linear(...))` and friends with default ranges; use the underlying generator for other bounds or shrink origins. Single-character generators are the `ascii_*` family (`ascii_lower`, `ascii_upper`, `ascii_letter`, `ascii_digit`, `ascii_alphanumeric`, `ascii_printable`), and each `string_*` shortcut wraps one with a length range.

`bit_array_printable` keeps every byte in printable ASCII (`0x20`..`0x7E`), for parsers that take a `BitArray` of headers or MIME types. `bit_array_utf8` always decodes back to a string; its `len` counts codepoints, so the byte length can be larger.

`generator.string_unicode(len)` and `generator.unicode_codepoint()` produce valid UTF-8 scalar values only. `generator.float(lo, hi)` is finite only; for NaN and `±Infinity` use `generator.float_special()` or `with_examples(my_float_gen, generator.float_special_edges())`. [doc/limitations.md](doc/limitations.md) covers UTF-8 surrogates, Unicode normalisation, and float differences between BEAM and JavaScript.

### Building record-shaped values

Use `map2` … `map8` (and `tuple2` … `tuple8`). Applicative composition shrinks every component, which nested `bind` does not.

```gleam
import metamon
import metamon/generator
import metamon/generator/range

pub type User {
  User(name: String, age: Int)
}

pub fn user_age_in_bounds_test() {
  let user_gen =
    generator.map2(
      generator.string_ascii(range.constant(1, 8)),
      generator.int(range.constant(0, 120)),
      User,
    )
  metamon.forall(user_gen, fn(u: User) { u.age >= 0 && u.age <= 120 })
}
```

### `one_of`, `element_of`, `frequency`

```gleam
import metamon
import metamon/generator

pub fn traffic_light_test() {
  let traffic_light =
    generator.frequency([
      #(3, generator.return("green")),
      #(2, generator.return("yellow")),
      #(1, generator.return("red")),
    ])
  metamon.forall(traffic_light, fn(colour) {
    colour == "green" || colour == "yellow" || colour == "red"
  })
}
```

`one_of` picks uniformly from a list of generators. `element_of` picks uniformly from a list of values without wrapping each in `return`:

```gleam
import metamon
import metamon/generator

pub fn extension_is_known_test() {
  metamon.forall(
    generator.element_of(["html", "json", "png", "pdf"]),
    fn(ext) {
      ext == "html" || ext == "json" || ext == "png" || ext == "pdf"
    },
  )
}
```

`element_of([])` panics, as `one_of([])` does. Every value becomes an edge, so the runner tries each one before sampling.

### `with_examples`

The runner tries edges before random inputs. `with_examples` adds must-try inputs, such as ones from past bug reports:

import metamon
import metamon/generator
import metamon/generator/range
import gleam/string

pub fn trim_idempotent_with_examples_test() {
  let trim_idempotent =
    metamon.idempotency_of(
      name: "trim_idempotent_with_examples",
      of: string.trim,
    )
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 8))
      |> generator.with_examples(["", " ", "  ", "\t\n  hi  \n\t"]),
    trim_idempotent,
    string.trim,
  )
}
```

### Recursive generators

`recursive(base, step)` halves `size` on each recursion, so it always terminates. At `size = 0` only `base` is used.

```gleam
import metamon
import metamon/generator
import metamon/generator/range

pub type Tree {
  Leaf(Int)
  Node(Tree, Tree)
}

pub fn tree_has_leaves_test() {
  let tree_gen =
    generator.recursive(
      generator.map(generator.int(range.constant(0, 9)), Leaf),
      fn(smaller) {
        generator.map2(smaller, smaller, Node)
      },
    )
  metamon.forall(tree_gen, fn(t) {
    case count_leaves(t) {
      n -> n >= 1
    }
  })
}
```

## Transforms and relations

### Composing transforms

```gleam
import metamon/transform
import gleam/string
import gleeunit/should

pub fn lowercase_then_trim_test() {
  let normalise =
    transform.then(
      transform.new("lowercase", string.lowercase),
      transform.new("trim", string.trim),
    )
  should.equal(normalise.apply("  Hello  "), "hello")
  should.equal(normalise.name, "lowercase |> trim")
}
```

### Combining relations

```gleam
import metamon/relation
import gleeunit/should

pub fn and_combination_test() {
  let positive =
    relation.new("positive_left", fn(left: Int, _right: Int) { left > 0 })
  let nonzero_right =
    relation.new("nonzero_right", fn(_left: Int, right: Int) { right != 0 })
  let combined = relation.and(positive, nonzero_right)
  should.be_true(combined.holds(5, 3))
  should.be_false(combined.holds(0, 3))
}
```

`relation.or`, `relation.invert` and `relation.implies` complete the Boolean set. Shortcut relations cover common domain shapes:

```gleam
import metamon/relation
import gleam/int
import gleeunit/should

pub fn approximately_test() {
  // approximately(epsilon): Float equality with a tolerance.
  let approx = relation.approximately(0.0001)
  should.be_true(approx.holds(0.1 +. 0.2, 0.3))
}

pub fn permutation_of_test() {
  // permutation_of: two lists are equal as multisets.
  let perm = relation.permutation_of()
  should.be_true(perm.holds([3, 1, 2], [1, 2, 3]))
}

pub fn subset_of_test() {
  // subset_of: multiset subset — every element of left is matched
  // against a *distinct* element of right (so [1, 1] is not a
  // subset of [1] because the second 1 has no match left).
  let sub = relation.subset_of()
  should.be_true(sub.holds([2, 3], [1, 2, 3, 4]))
  should.be_false(sub.holds([1, 1], [1]))
  should.be_true(sub.holds([1, 1], [1, 1, 2]))
}

pub fn set_subset_of_test() {
  // set_subset_of: set subset — every element of left is contained
  // somewhere in right, ignoring multiplicity. Reach for this when
  // the lists are header-style (presence matters, count does not).
  let sub = relation.set_subset_of()
  should.be_true(sub.holds([1, 1], [1]))
  should.be_true(sub.holds([2, 3], [1, 2, 3, 4]))
  should.be_false(sub.holds([1, 4], [1, 2, 3]))
}

pub fn monotone_test() {
  // monotone(cmp): holds when cmp(left, right) is Lt or Eq. Useful
  // for monotonic-by-construction functions (list.sort, list.scan,
  // ...).
  let mono = relation.monotone(int.compare)
  should.be_true(mono.holds(3, 5))
}
```

### `equivalent_under`

```gleam
import metamon/relation
import gleam/string
import gleeunit/should

pub fn case_insensitive_test() {
  let r =
    relation.equivalent_under(string.lowercase, "case_insensitive")
  should.be_true(r.holds("Hello", "HELLO"))
  should.be_false(r.holds("Hello", "World"))
}
```

## Coverage and annotations

### `cover` and `classify`

`cover(target, label, condition)` requires the labelled hits to reach `target%` of all inputs. The property fails when coverage falls short, even if every run passed:

```gleam
import metamon
import metamon/coverage
import metamon/generator
import metamon/generator/range
import gleam/string

pub fn trim_never_grows_input_test() {
  metamon.forall(
    generator.string_ascii(range.constant(0, 8)),
    fn(s) {
      coverage.cover(5.0, "non_empty", string.length(s) > 0)
      coverage.classify("contains_space", string.contains(s, " "))
      string.length(string.trim(s)) <= string.length(s)
    },
  )
}
```

### `annotate` and `footnote`

These print nothing unless the property fails:

```gleam
import metamon
import metamon/annotate
import metamon/generator
import metamon/generator/range
import gleam/int

pub fn annotated_property_test() {
  metamon.forall(
    generator.int(range.constant(0, 100)),
    fn(n) {
      annotate.annotate("currently checking n = " <> int.to_string(n))
      annotate.annotate_value("doubled", n * 2)
      annotate.footnote("hint: n is non-negative by construction")
      n >= 0
    },
  )
}
```

## JSON output

`with_output_format(config.Json)` replaces the text report with a single-line JSON object:

```gleam
import metamon
import metamon/config
import metamon/generator
import metamon/generator/range

pub fn json_output_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  metamon.forall_with(
    cfg,
    generator.int(range.constant(0, 100)),
    fn(n) { n >= 0 },
  )
}
```

The schema is stable. Top-level keys: `mr_name`, `test_name`,
`config_seed`, `runs_done`, `runs_total`, `shrinks_done`,
`shrink_capped`, `source`, `morph_mode`, `relation`, `source_input`,
`followup_input`, `source_output`, `followup_output`, `annotations`,
`footnotes`, `coverage`.

## N-ary metamorphic relations

`forall_morph_n` takes a list of input transforms and a `RelationN` that compares all the outputs at once:

```gleam
import gleam/list
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform/list as list_t

fn list_sum(items: List(Int)) -> Int {
  list.fold(items, 0, fn(acc, n) { acc + n })
}

pub fn sum_under_three_invariants_test() {
  metamon.forall_morph_n(
    generator.list_of(
      generator.int(range.constant(0, 9)),
      range.constant(0, 4),
    ),
    [list_t.reverse(), list_t.append(0)],
    relation.all_equal(),
    list_sum,
  )
}
```

`relation.all_equal()` requires every output to be equal; `relation.pairwise(r)` checks a binary relation along the chain.

## Stateful / model-based testing

Run a list of `Command(model, real)` against a model and a real system side by side:

```gleam
import gleam/dict
import gleeunit/should
import metamon/command
import metamon/stateful

type Model {
  Model(value: Int)
}

type Real {
  Real(state: dict.Dict(String, Int))
}

pub fn counter_increments_test() {
  let increment =
    command.always(
      name: "increment",
      next_model: fn(m: Model) { Model(value: m.value + 1) },
      run: fn(_real: Real) { Ok(Nil) },
    )
  let initial_model = Model(value: 0)
  let initial_real = Real(state: dict.from_list([#("counter", 0)]))
  let outcome =
    stateful.run(initial_model, initial_real, [increment, increment])
  case outcome {
    stateful.Passed(final, _, _) -> should.equal(final, Model(value: 2))
    stateful.Failed(_, _, _, _) -> should.fail()
  }
}
```

`command.no_precondition` (alias `command.always`, kept for backward compatibility) has no precondition; `command.new` gates a command on the current model. A command's `run` can still return `Error(reason)`, which halts the sequence with `Failed`, and `stateful.assert_passed` then panics with a structured message.

`stateful.run([])` panics, because an empty command list tests nothing. `stateful.assert_passed` also panics on `Passed(_, ran: 0, skipped: N)` with `N > 0`: every precondition returned `False`, so model and real were never compared.

## Case study: CRDT algebraic laws

[doc/crdt-case-study.md](doc/crdt-case-study.md) checks the idempotency, commutativity and associativity of a G-Counter `merge` with `forall`.

## Configuration

The `with_*` builders that can be given invalid values return `Result(Config, ConfigError)` instead of falling back to a default.

```gleam
import metamon
import metamon/generator
import metamon/generator/range

pub fn configured_property_test() {
  let assert Ok(c) =
    metamon.with_runs(
      metamon.default_config()
        |> metamon.with_seed(metamon.seed(2026)),
      30,
    )
  metamon.forall_with(
    c,
    generator.int(range.constant(-100, 100)),
    fn(n) { n + 0 == n },
  )
}
```

`with_runs`, `with_max_size`, `with_shrink_limit`, `with_max_edges` and `with_regression_file` return `Result(Config, ConfigError)`. `with_seed` and `with_diff_enabled` are total.

Setting `METAMON_RUNS_MULTIPLIER` to a positive integer multiplies every property's run count, so a nightly CI job can explore far more inputs than a pull request without editing a test: `METAMON_RUNS_MULTIPLIER=100 gleam test`. Any other value stops the run with an error. The failure report prints the seed, so a failure found this way can be reproduced with `with_seed`.

## Reading a failure report

The panic message has these blocks; only the ones that apply appear:

```
× metamorphic relation `<mr.name>` failed
  test:        <gleeunit test name>
  source:      edge(<i>) | random(seed=<n>, size=<n>, max_size=<n>)
  config seed: <integer>
  runs:        <i> / <total>
  shrinks:     <count> | <count>+ (limit reached)

  transform:   `<input transform name>`
  output:      `<output transform name>`     ; equivariant only
  relation:    `<relation name>`

  source input  (shrunk):
    <pretty-printed input>
  follow-up input  (= transform(source)):
    <pretty-printed input>
  source output:
    <pretty-printed output>
  follow-up output:
    <pretty-printed output>

  diff (source_output vs follow-up_output):
    <structural diff>

  annotations:
    - <annotate calls in registration order>

  coverage:
    <label>: <hits>/<total> (<pct>%) target≥<target>%

  footnotes:
    - <footnote calls>

  reproduce (paste into a test):
    // The MR failed for this input. To pin it as a regression,
    // call assert_morph with the shrunk input and the same MR.
    let input = <pretty-printed shrunk input>
    metamon.assert_morph(input, mr, f)
```

To keep a failing input, paste the `reproduce` block into a test as a literal, or use `with_regression_file(path)`: the runner appends each failure to a TOML file and re-runs every entry before random generation.

## Choosing PBT vs MT vs `assert_morph`

| You want to test | Reach for |
|---|---|
| "for every input the answer satisfies P" | `metamon.forall` |
| "transforming the input in this way preserves the output" | `metamon.forall_morph` with `invariant_under` or `idempotency_of` |
| "transforming the input in this way changes the output in this way" | `metamon.forall_morph` with `equivariant_under` or a hand-built MR |
| "this one specific input must always pass this MR" | `metamon.assert_morph` |
| "all of these MRs must hold for the same `f`" | `metamon.forall_morphs` |

`forall_morphs([])`, and `forall_morph_n` or `forall_morph_n_with` with an empty `transforms` list, panic with "empty MR list (vacuous test)". Use `forall(...)` when there is no MR.

## Modules

The full API is on [HexDocs](https://hexdocs.pm/metamon/).

| Module | Responsibility |
|---|---|
| `metamon` | Runners (`forall*`, `forall_morph*`, `assert_morph`, `forall_round_trip*`), MR templates, `Mr`, seeds and config re-exports |
| `metamon/config` | `Config`, `ConfigError` and the `with_*` builders |
| `metamon/generator` | `Generator(a)`, combinators (`map`, `bind`, `map2`..`map8`, `one_of`, `frequency`, `recursive`, ...) and generators for numbers, strings, bit arrays and collections |
| `metamon/generator/seed` | xorshift32-based `Seed` with `split` (target-portable; identical streams on BEAM and JS) |
| `metamon/generator/tree` | Lazy rose tree used as the integrated shrink representation |
| `metamon/generator/range` | `singleton`, `constant`, `linear`, `linear_from`, `exponential` (Hedgehog-style ranges) |
| `metamon/transform` | `Transform(a)`, `new`, `identity`, `constant`, `then`, `repeat`, `rename` |
| `metamon/transform/list`   | `reverse`, `dedupe`, `prepend`, `append`, `shuffle` |
| `metamon/transform/string` | `reverse`, `lowercase`, `uppercase`, `trim`, `prepend`, `append` |
| `metamon/transform/dict`   | `insert`, `remove`, `shuffle_keys` |
| `metamon/relation` | `Relation(b)` and `RelationN(b)` with equality, approximate, multiset and set relations and Boolean combinators |
| `metamon/diff` | Structural diff used in failure reports |
| `metamon/annotate` | `annotate`, `annotate_value`, `footnote` and accessors |
| `metamon/coverage` | `classify`, `cover` and coverage inspection |
| `metamon/command` | `Command(model, real)` for model-based testing |
| `metamon/stateful` | `run`, `assert_passed`, `Outcome` (model-based test runner) |

## Compatibility

- Gleam 1.14+ (CI covers 1.14.0 and the latest 1.x).
- BEAM target: Erlang/OTP 27 or later (CI covers OTP 27, 28 and 29).
- JavaScript target: Node.js 22 or later (CI covers Node 22 and the current LTS).

[doc/targets.md](doc/targets.md) covers the runtime dependency footprint and behaviour differences between BEAM and JavaScript. [doc/limitations.md](doc/limitations.md) lists known scope cuts and workarounds (`bind` shrinking, `recursive` branch-swap, `filter` retry limit, JS parallel runners, UTF-8 surrogate exclusion, float special values).

## Testing

| Technique | Bug class caught here |
|---|---|
| Examples and unit tests | [Wrong generator bounds, edges, shrinks and reports](doc/testing.md#examples-and-unit-tests) |
| Generated properties | [Broken generator laws and runner invariants, checked by metamon itself](doc/testing.md#generated-properties) |
| Metamorphic relations | [Relation checks that pass when outputs differ](doc/testing.md#metamorphic-relations) |
| Contracts | [Changes to the stable JSON report, quadratic slowdowns](doc/testing.md#contracts) |
| Mutation testing | [Assertions that miss a changed operator or branch](doc/testing.md#mutation-testing) |

## Development

This project uses [mise](https://mise.jdx.dev/) to manage Gleam and
Erlang versions, and [just](https://just.systems/) as a task runner.

```sh
mise install    # install Gleam and Erlang
just ci         # download deps and run all checks
just test       # gleam test
just format     # gleam format
just check      # all checks without deps download
```

## Contributing

Contributions are welcome. See
[CONTRIBUTING.md](https://github.com/nao1215/metamon/blob/main/CONTRIBUTING.md)
for details.

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`metamon-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`metamon-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify metamon-<version>.tar --repo nao1215/metamon

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/metamon/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/metamon/blob/main/LICENSE)
