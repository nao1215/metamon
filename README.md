# metamon

[![CI](https://github.com/nao1215/metamon/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/metamon)](https://hex.pm/packages/metamon)

Property-based testing and metamorphic testing combinator library for
Gleam.

metamon treats both styles of testing as first-class concepts:

- Property-based testing (PBT): state a single-input predicate and let
  metamon search the input space for counter-examples.
- Metamorphic testing (MT): state a relation between outputs produced
  by two related inputs (e.g. `f(x)` and `f(reverse(x))`) and let
  metamon search for inputs where the relation breaks.

Every snippet on this page is the body of a `pub fn readme_*_test` in
[`test/readme_test.gleam`](test/readme_test.gleam) and is checked by
`gleam test` on every CI run, so the examples cannot drift out of
sync with the API.

## Table of contents

- [Install](#install)
- [Quick start](#quick-start)
- [Property-based testing](#property-based-testing)
- [Metamorphic relations](#metamorphic-relations)
- [Round-trip variants](#round-trip-variants)
- [Generators](#generators)
- [Transforms and relations](#transforms-and-relations)
- [Coverage and annotations](#coverage-and-annotations)
- [JSON output](#json-output)
- [N-ary metamorphic relations](#n-ary-metamorphic-relations)
- [Stateful / model-based testing](#stateful--model-based-testing)
- [Configuration](#configuration)
- [Reading a failure report](#reading-a-failure-report)
- [Choosing PBT vs MT vs `assert_morph`](#choosing-pbt-vs-mt-vs-assert_morph)
- [Modules](#modules)
- [Compatibility](#compatibility)
- [Further reading](#further-reading)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Install

```sh
gleam add metamon --dev
```

Requirements: Gleam 1.15+, Erlang/OTP 27+, Node.js 22+.

See [doc/targets.md](doc/targets.md) for target details and the
runtime dependency footprint.

## Quick start

The smallest useful test states a metamorphic relation. `string.trim`
is idempotent — applying it twice gives the same result as applying
it once. metamon ships a template for this exact shape.

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

If `string.trim` ever stops being idempotent, the test panics with a
named report:

```
× metamorphic relation `trim_idempotent` failed
  test:        forall_morph
  source:      random(seed=..., size=12)
  config seed: 1714867200000123
  runs:        7 / 100
  shrinks:     4

  transform:   `apply trim_idempotent`
  relation:    `equal`

  source input  (shrunk):
    "  a"
  ...
```

## Property-based testing

### `forall`

`metamon.forall` runs a single-argument predicate against many
generated inputs:

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

### `forall_observable` — show the predicate's intermediate value

When the branch in the predicate hinges on an intermediate value
(`f(input)`), the plain `forall` failure report only shows the shrunk
source input, not what the predicate was actually inspecting.
`forall_observable` lets the predicate return `#(observation, holds)`;
the observation is rendered into the failure report under the label
`predicate value`:

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

This is equivalent to a plain `forall` plus a manual
`annotate.annotate_value("predicate value", trimmed)`; the helper
saves that one line and makes the intent explicit.

## Metamorphic relations

A metamorphic relation says "if you transform the input in this known
way, the output should change in this known way." metamon ships
templates for the most common shapes.

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

`f` and `inverse` should round-trip cleanly. `forall_round_trip` is
the one-liner — the failure report header is `round_trip[<name>]` so
it is immediately obvious from the panic which round-trip broke:

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

Round-trip is not exposed as an `Mr` template because the relation
compares the decoded output against the source input, which the
two-point `f(source) ⟷ f(transform(source))` shape of an MR cannot
express directly. `forall_round_trip` wraps `forall` instead, so the
error reports retain the same shrunk-source rendering.

### Invariance: `f(T(x)) == f(x)`

The function is unaffected by the transformation. `list.length` is
invariant under `reverse`:

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

The output also transforms in a known way. `map(g)` commutes with
`reverse`:

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

When the four templates above don't fit, build the MR by hand from a
`Transform(a)` and a `Relation(b)`:

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

### `assert_morph` — single hand-supplied input

No generator, just a fixed input. Useful for regression tests of a
specific failing case:

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

The `commutativity_of` template builds an MR over the input pair
`#(a, a)` whose transform swaps the two components:

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

### `forall_morphs` — multiple MRs against the same `f`

Each MR is exercised independently and the runner reports all
failures, not just the first:

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

> **Tip — encoder / decoder libraries.** If your library exposes a
> paired `encode` / `decode`, a single `forall_round_trip` call
> exercises a useful first invariant with no per-input handwriting.
> Drop this into `test/` as a starter property:
>
> ```gleam
> import metamon
> import metamon/generator
> import metamon/generator/range
>
> pub fn encode_decode_round_trip_test() {
>   metamon.forall_round_trip(
>     gen: generator.bit_array(range.constant(0, 64)),
>     name: "my_codec",
>     encode: my_codec.encode,
>     decode: my_codec.decode,
>   )
> }
> ```
>
> The two variants below
> (`forall_round_trip_partial` and `forall_round_trip_under`) cover
> the common shapes a real codec hits — partial encoders that reject
> some inputs, and decoded forms that compare equal only under a
> normalising projection.

`forall_round_trip` requires `encode: a -> b` and
`decode: b -> Result(a, _)`. Real codec libraries often produce
`encode: a -> Result(b, _)` (when not every input is valid for the
codec) or have a source type whose decoded form does not compare equal
under structural `==`. Two named variants cover both cases without a
hand-rolled shim.

### Partial encoder — `forall_round_trip_partial`

Inputs the encoder rejects are skipped (treated as out of scope, not
failures). Useful for codecs with structural preconditions
(byte-alignment, version range, hrp / variant constraints, etc.).

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

### Custom equality — `forall_round_trip_under`

Pass a `Relation(a)` instead of structural `==`. Useful for opaque
types whose decoded form normalises (multipart `Part` re-deriving its
`name` / `filename` cache, MIME types whose essence lowercases, etc.).
Combine with `relation.equivalent_under(via, name)` to compare on a
projection.

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

These wrap `generator.int(range.linear(...))` etc. with sensible
default ranges. Reach for the underlying `generator.int(...)` when you
need different bounds or shrink origins.

For single-character generators (`a-zA-Z`, `0-9`, etc.), see the
`ascii_*` family in the [Modules](#modules) table:
`ascii_lower`, `ascii_upper`, `ascii_letter`, `ascii_digit`,
`ascii_alphanumeric`, `ascii_printable`. The `string_*` shortcuts
above wrap each of those with a length range.

`bit_array_printable` constrains every byte to printable ASCII
(`0x20`..`0x7E`) — useful when fuzzing parsers that take `BitArray`
but expect printable input (HTTP headers, MIME types, etc.).
`bit_array_utf8` produces a `BitArray` that is guaranteed to decode
back to a string; the `len` argument is the codepoint count, so the
byte length will be larger when the random string contains multi-byte
codepoints.

`generator.string_unicode(len)` and `generator.unicode_codepoint()`
produce valid UTF-8 scalar values only. `generator.float(lo, hi)` is
finite-only. For genuinely-NaN / `±Infinity` inputs, use
`generator.float_special()` or splice the special values via
`with_examples(my_float_gen, generator.float_special_edges())`. See
[doc/limitations.md](doc/limitations.md) for the full caveats around
UTF-8 surrogates, Unicode normalisation, and BEAM vs JavaScript float
behaviour.

### Building record-shaped values

Use `map2` … `map8` (and the matching `tuple2` … `tuple8`) for
record-shaped generators. Prefer applicative composition over nested
`bind` so integrated shrinking applies on every component.

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

`one_of` picks uniformly from a list of generators. For the common
case of "pick uniformly from a fixed set of values", `element_of`
skips the per-value `return` wrap:

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

`element_of` panics when the list is empty (mirroring `one_of([])`).
Every value becomes an edge, so the runner tries each one before
sampling.

### `with_examples` — guarantee specific inputs are tried

The runner consumes `edges` first, before random generation. Use
`with_examples` to add must-try inputs from past bug reports:

```gleam
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

`recursive(base, step)` halves `size` on each recursion, so it always
terminates. At `size = 0` only `base` is used.

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

`relation.or`, `relation.invert`, `relation.implies` complete the
Boolean set. For the most common domain shapes, four shortcut
combinators skip the `and` / custom-`new` plumbing entirely:

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

### `equivalent_under` — relation on a normalised view

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

`cover(target, label, condition)` asserts that the labelled hits
account for at least `target%` of all inputs. The property fails even
when every individual run passed if coverage falls short:

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

These are silent on success and surface only on failure, so liberal
use is cheap:

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

Set the output format on a per-test config to swap the human-readable
text for a single-line JSON object:

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
`footnotes`, `coverage`. Pipe to `jq`, post to GitHub Actions
annotations, or feed into an LLM analysis step.

## N-ary metamorphic relations

When the relation must compare more than two outputs in one shot,
hand `forall_morph_n` a list of input transforms and a `RelationN`:

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

`relation.all_equal()` asserts every output is structurally equal;
`relation.pairwise(r)` lifts a binary relation to a chain check.

## Stateful / model-based testing

For state machines, build a list of `Command(model, real)` and run it
against a parallel `(model, real)` pair:

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

`command.no_precondition` (alias: `command.always`) skips the
precondition; use `command.new` to gate commands on the current model.
"No precondition" is not the same as "always runs" — the command's
`run` step can still return `Error(reason)`, which halts the sequence
and reports `Failed`. `stateful.assert_passed` panics with a
structured failure message when that happens. Prefer the
`no_precondition` name in new code; the `always` alias is kept for
backward compatibility.

`stateful.run` requires at least one `Command`; passing `[]` is a
programming error (vacuous test) and panics with a structured message.
Use `forall(...)` if you need a non-stateful property instead.

`stateful.assert_passed` also panics when every command's
`precondition` returned `False` — i.e. the outcome is
`Passed(_, ran: 0, skipped: N)` with `N > 0`. The test never compared
model and real, so silently passing would hide precondition or
initial-model bugs. Adjust the preconditions or initial model so at
least one command fires.

## Configuration

Override the defaults via `with_*` builders. Validation errors return
`Result(Config, ConfigError)` instead of silently falling back to a
default.

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

`with_runs`, `with_max_size`, `with_shrink_limit`, `with_max_edges`,
`with_regression_file` all return `Result(Config, ConfigError)`.
`with_seed` and `with_diff_enabled` are total.

## Reading a failure report

Failures are panics whose message is structured for human reading.
Every block is optional; only the parts that apply to your test
appear:

```
× metamorphic relation `<mr.name>` failed
  test:        <gleeunit test name>
  source:      edge(<i>) | random(seed=<n>, size=<n>)
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

The `reproduce` block paired with `metamon.with_regression_file(...)`
gives you two ways to keep failing inputs around:

- Reproduce block (in-test): paste the shrunk input directly into a
  Gleam test as a literal. Survives regardless of the runner state.
- Regression file (`with_regression_file(path)`): the runner appends
  each failure to a TOML file and re-runs every entry on startup
  before any random generation. Useful when you want past failures
  rerun on every CI build without changing the test source.

## Choosing PBT vs MT vs `assert_morph`

| You want to test | Reach for |
|---|---|
| "for every input the answer satisfies P" | `metamon.forall` |
| "transforming the input in this way preserves the output" | `metamon.forall_morph` with `invariant_under` or `idempotency_of` |
| "transforming the input in this way changes the output in this way" | `metamon.forall_morph` with `equivariant_under` or a hand-built MR |
| "this one specific input must always pass this MR" | `metamon.assert_morph` |
| "all of these MRs must hold for the same `f`" | `metamon.forall_morphs` |

`forall_morphs` requires ≥ 1 MR; passing `[]` panics with a structured
"empty MR list (vacuous test)" message — use `forall(...)` for the
no-MR case. Same applies to `forall_morph_n` and `forall_morph_n_with`
with an empty `transforms` list.

## Modules

| Module | Responsibility |
|---|---|
| `metamon` | Top-level API: `forall`, `forall_with`, `forall_observable`, `forall_observable_with`, `forall_morph`, `forall_morph_with`, `forall_morph_n`, `forall_morph_n_with`, `assert_morph`, `forall_morphs`, `forall_round_trip`, `forall_round_trip_with`, `forall_round_trip_partial`, `forall_round_trip_partial_with`, `forall_round_trip_under`, `forall_round_trip_under_with`, `Mr` (opaque), `mr`, `mr_equivariant`, `name_of`, `idempotency_of`, `invariant_under`, `equivariant_under`, `commutativity_of`, `OutputFormat`, `with_output_format`, `seed`, `random_seed`, `default_config` and all `with_*` re-exports |
| `metamon/config` | `Config`, `ConfigError`, `default_config`, `with_runs`, `with_seed`, `with_max_size`, `with_shrink_limit`, `with_max_edges`, `with_regression_file`, `with_diff_enabled` |
| `metamon/generator` | `Generator(a)` (opaque), `generate`, `sample`, `statistics`, `with_examples`, `add_edges`, `no_edges`, `return`, `map`, `bind`, `map2`..`map8`, `tuple2`..`tuple8`, `one_of`, `element_of`, `frequency`, `sized`, `resize`, `scale`, `filter`, `recursive`, `int`, `float`, `float_special`, `float_special_edges`, `bool`, `non_negative_int`, `positive_int`, `negative_int`, `byte`, `bit_array`, `bit_array_printable`, `bit_array_utf8`, `ascii_*`, `unicode_codepoint`, `string`, `string_ascii`, `string_alpha`, `string_alphanumeric`, `string_digit`, `string_printable_ascii`, `string_unicode`, `list_of`, `non_empty_list_of`, `dict_of`, `set_of`, `option_of`, `result_of` |
| `metamon/generator/seed` | xorshift32-based `Seed` with `split` (target-portable; identical streams on BEAM and JS) |
| `metamon/generator/tree` | Lazy rose tree used as the integrated shrink representation |
| `metamon/generator/range` | `singleton`, `constant`, `linear`, `linear_from`, `exponential` (Hedgehog-style ranges) |
| `metamon/transform` | `Transform(a)`, `new`, `identity`, `constant`, `then`, `repeat`, `rename` |
| `metamon/transform/list`   | `reverse`, `dedupe`, `prepend`, `append`, `shuffle` |
| `metamon/transform/string` | `reverse`, `lowercase`, `uppercase`, `trim`, `prepend`, `append` |
| `metamon/transform/dict`   | `insert`, `remove`, `shuffle_keys` |
| `metamon/relation` | `Relation(b)`, `new`, `equal`, `not_equal`, `equivalent_under`, `approximately`, `permutation_of`, `subset_of` (multiset), `set_subset_of` (set), `monotone`, `implies`, `and`, `or`, `invert`, `rename`, `RelationN(b)`, `n_new`, `all_equal`, `pairwise` (N-ary relations for `forall_morph_n`) |
| `metamon/diff` | Structural diff used in failure reports: `diff`, `diff_string`, `render`, `Same`/`Differ`/`ListDiff`/`TupleDiff`/`StringDiff` |
| `metamon/annotate` | `annotate`, `annotate_value`, `footnote`, `reset`, `current_annotations`, `current_footnotes` |
| `metamon/coverage` | `classify`, `cover`, `cover_at_least`, `classify_in_bucket`, `collect`, `snapshot`, `shortfalls`, `actual_pct`, `target_pct_of`, `requirements_of`, `collected_of`, `hits_for`, `first_shortfall`, `Pct`/`Count` requirement kinds |
| `metamon/command` | `Command(model, real)`, `new`, `no_precondition`, `always` (alias of `no_precondition`), `name_of` (model-based testing primitive) |
| `metamon/stateful` | `run(initial_model, initial_real, commands)`, `assert_passed`, `Outcome` (model-based test runner) |

## Compatibility

- Gleam 1.15+
- BEAM target: Erlang/OTP 27 or later (CI covers OTP 27 and 28).
- JavaScript target: Node.js 22 or later (CI covers Node 22 and 24).

See [doc/targets.md](doc/targets.md) for the full target story,
runtime dependency footprint, and behavioural differences between
BEAM and JavaScript.

## Further reading

- [doc/limitations.md](doc/limitations.md): known scope cuts and
  workarounds (`bind` shrinking, `recursive` branch-swap, `filter`
  retry limit, JS parallel runners, UTF-8 surrogate exclusion, float
  special-value asymmetry).
- [doc/targets.md](doc/targets.md): supported targets, runtime
  requirements, dependency footprint.

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

## License

[MIT](https://github.com/nao1215/metamon/blob/main/LICENSE)
