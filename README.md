# metamon

[![CI](https://github.com/nao1215/metamon/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/metamon)](https://hex.pm/packages/metamon)

Property-based testing **and** metamorphic testing combinator library
for Gleam.

metamon treats both styles of testing as first-class concepts:

- **Property-based testing (PBT)**: state a single-input predicate
  and let metamon search the input space for counter-examples.
- **Metamorphic testing (MT)**: state a relation between outputs
  produced by *two* related inputs (e.g. `f(x)` and `f(reverse(x))`)
  and let metamon search for inputs where the relation breaks.

Design notes:

- Metamorphic relations are named values with input transforms,
  output transforms (for equivariance), and binary relations — every
  failure report tells you which relation broke.
- Integrated rose-tree shrinking is always on. Generators carry their
  own shrink strategy; combinators preserve it automatically.
- Edge cases (`0`, `Int.max`, `""`, surrogates, ...) are tried before
  random inputs. `with_examples` lets you bolt on more.
- Coverage assertions (`cover` / `classify` / `collect`) make
  distribution gaps visible before they hide bugs.
- `annotate` / `footnote` attach context to a property; output is
  free on success, displayed on failure.
- Failures include source / follow-up inputs, both outputs, a
  structural diff, and a reproducer snippet.
- Zero external dependencies — only `gleam_stdlib`. No PBT library
  is wrapped; everything (Seed, Tree, Range, Generator, Shrink,
  Runner) is implemented in metamon itself.

## Requirements

- Gleam 1.15 or later
- Erlang/OTP 27 or later (when targeting Erlang)
- Node.js 18 or later (when targeting JavaScript)

## Supported targets

- Erlang (BEAM) — full surface, used for everyday Gleam tests.
- JavaScript — the Generator / Tree / Seed core is pure Gleam, but
  `metamon/annotate` and `metamon/coverage` rely on a thin FFI shim
  for per-process state. The JS shim uses a module-level `Map`, so
  the runner clears it between properties.

## Install

```sh
gleam add metamon --dev
```

## Quick start

The smallest useful test states a metamorphic relation. `string.trim`
is *idempotent* — applying it twice gives the same result as applying
it once. metamon ships a template for this exact shape.

```gleam
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

pub fn trim_idempotent_test() {
  let mr = metamon.idempotency_of(string.trim, "trim_idempotent")
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

## How to use

The headings below correspond 1:1 to test functions in
[`test/readme_test.gleam`](test/readme_test.gleam). Every snippet on
this page is the body of a `pub fn readme_*_test` and is checked by
`gleam test` on every CI run, so the examples cannot drift out of
sync with the API.

### 1. Property-based testing — `forall`

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

### 2. Metamorphic relations

A metamorphic relation says "if you transform the input in this
known way, the output should change in this known way." metamon
ships templates for the most common shapes.

#### 2.1. Idempotency: `f(f(x)) == f(x)`

```gleam
import metamon
import metamon/generator
import metamon/generator/range

pub fn sort_dedupe_idempotent_test() {
  let mr = metamon.idempotency_of(sort_dedupe, "sort_dedupe_idempotent")
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

#### 2.2. Round-trip via a custom relation

`f` and `inverse` should round-trip cleanly. Build a `Relation` that
checks the recovered value:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import gleam/int

pub fn int_string_round_trip_test() {
  let r =
    relation.new("string_int_round_trip", fn(left: Int, right: Int) {
      left == right
    })
  let mr =
    metamon.mr(
      name: "int_string_round_trip",
      transform: transform.identity(),
      relation: r,
    )
  metamon.forall_morph(
    generator.int(range.constant(-1000, 1000)),
    mr,
    fn(n) {
      let assert Ok(parsed) = int.parse(int.to_string(n))
      parsed
    },
  )
}
```

#### 2.3. Invariance: `f(T(x)) == f(x)`

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
    metamon.invariant_under(list_t.reverse(), "length_invariant_under_reverse")
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

#### 2.4. Equivariance: `U(f(x)) == f(T(x))`

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
      list_t.reverse(),
      list_t.reverse(),
      relation.equal(),
      "map_commutes_with_reverse",
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

#### 2.5. Manual MR construction

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

#### 2.6. `assert_morph` — single hand-supplied input

No generator, just a fixed input. Useful for regression tests of a
specific failing case:

```gleam
import metamon
import metamon/transform/list as list_t

pub fn sum_reverse_regression_test() {
  let mr =
    metamon.invariant_under(list_t.reverse(), "sum_invariant_under_reverse")
  metamon.assert_morph([1, 2, 3, 4, 5], mr, list_sum)
}
```

#### 2.7. `forall_morphs` — multiple MRs against the same `f`

Each MR is exercised independently and the runner reports all
failures, not just the first:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import metamon/transform/list as list_t

pub fn sum_multi_mr_test() {
  let invariant_under_reverse =
    metamon.invariant_under(list_t.reverse(), "sum_under_reverse")
  let invariant_under_append_zero =
    metamon.invariant_under(list_t.append(0), "sum_under_append_zero")
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

### 3. Generators

#### 3.1. Building record-shaped values with `map2`

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

`map3` / `map4` / `map5` / `map6` extend this to records of higher
arity. `tuple2` … `tuple5` are shortcuts for the tupling case.

#### 3.2. `one_of` and `frequency`

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

#### 3.3. `with_examples` — guarantee specific inputs are tried

The runner consumes `edges` first, *before* random generation. Use
`with_examples` to add must-try inputs from past bug reports:

```gleam
import metamon
import metamon/generator
import metamon/generator/range
import gleam/string

pub fn trim_idempotent_with_examples_test() {
  let trim_idempotent =
    metamon.idempotency_of(string.trim, "trim_idempotent_with_examples")
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 8))
      |> generator.with_examples(["", " ", "  ", "\t\n  hi  \n\t"]),
    trim_idempotent,
    string.trim,
  )
}
```

#### 3.4. Recursive generators

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

### 4. Transforms and relations

#### 4.1. Composing transforms

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

#### 4.2. Combining relations

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

`relation.or`, `relation.invert`, `relation.implies` complete the set.

#### 4.3. `equivalent_under` — relation on a normalised view

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

### 5. Coverage and annotations

#### 5.1. `cover` and `classify`

`cover(target, label, condition)` asserts that the labelled hits
account for at least `target%` of all inputs. The property fails
even when every individual run passed if coverage falls short:

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

#### 5.2. `annotate` and `footnote`

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

### 6. Configuration

Override the defaults via `with_*` builders. Validation errors
return `Result(Config, ConfigError)` instead of silently falling
back to a default.

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

`with_runs`, `with_max_size`, `with_shrink_limit`, `with_max_discards`,
`with_max_edges`, `with_regression_file` all return
`Result(Config, ConfigError)`. `with_seed` and `with_diff_enabled`
are total.

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

  reproduce:
    let assert Ok(c) =
      metamon.default_config()
      |> metamon.with_seed(metamon.seed(<seed>))
      |> metamon.with_runs(<i+1>)
    metamon.forall_morph_with(c, generator, mr, f)
```

The `reproduce` block can be pasted into a regression test to pin
the failing input forever.

## Modules

| Module | Responsibility |
|---|---|
| `metamon` | Top-level API: `forall`, `forall_with`, `forall_morph`, `forall_morph_with`, `assert_morph`, `forall_morphs`, `Mr` (opaque), `mr`, `mr_equivariant`, `name_of`, `idempotency_of`, `round_trip_with`, `invariant_under`, `equivariant_under`, `seed`, `random_seed`, `default_config` and all `with_*` re-exports |
| `metamon/config` | `Config`, `ConfigError`, `default_config`, `with_runs`, `with_seed`, `with_max_size`, `with_shrink_limit`, `with_max_discards`, `with_max_edges`, `with_regression_file`, `with_diff_enabled` |
| `metamon/generator` | `Generator(a)` (opaque), `generate`, `sample`, `statistics`, `with_examples`, `add_edges`, `no_edges`, `return`, `map`, `bind`, `map2`..`map6`, `tuple2`..`tuple5`, `one_of`, `frequency`, `sized`, `resize`, `scale`, `filter`, `recursive`, `int`, `float`, `ascii_*`, `unicode_codepoint`, `string`, `string_ascii`, `string_unicode`, `list_of`, `non_empty_list_of`, `dict_of`, `set_of`, `option_of`, `result_of` |
| `metamon/generator/seed` | splitmix64-based `Seed` with `split` |
| `metamon/generator/tree` | Lazy rose tree used as the integrated shrink representation |
| `metamon/generator/range` | `singleton`, `constant`, `linear`, `linear_from`, `exponential` (Hedgehog-style ranges) |
| `metamon/transform` | `Transform(a)`, `new`, `identity`, `always`, `then`, `repeat`, `rename` |
| `metamon/transform/list`   | `reverse`, `dedupe`, `prepend`, `append`, `shuffle` |
| `metamon/transform/string` | `reverse`, `lowercase`, `uppercase`, `trim`, `prepend`, `append` |
| `metamon/transform/dict`   | `insert`, `remove`, `shuffle_keys` |
| `metamon/relation` | `Relation(b)`, `new`, `equal`, `not_equal`, `equivalent_under`, `approximately`, `permutation_of`, `subset_of`, `monotone`, `implies`, `and`, `or`, `invert`, `rename` |
| `metamon/diff` | Structural diff used in failure reports: `diff`, `diff_string`, `render`, `Same`/`Differ`/`ListDiff`/`StringDiff` |
| `metamon/annotate` | `annotate`, `annotate_value`, `footnote`, `reset`, `current_annotations`, `current_footnotes` |
| `metamon/coverage` | `classify`, `cover`, `collect`, `snapshot`, `shortfalls`, `actual_pct`, `requirements_of`, `collected_of`, `hits_for`, `first_shortfall` |

## Choosing PBT vs MT vs `assert_morph`

| You want to test | Reach for |
|---|---|
| "for every input the answer satisfies P" | `metamon.forall` |
| "transforming the input in this way preserves the output" | `metamon.forall_morph` with `invariant_under` or `idempotency_of` |
| "transforming the input in this way changes the output in this way" | `metamon.forall_morph` with `equivariant_under` or a hand-built MR |
| "this one specific input must always pass this MR" | `metamon.assert_morph` |
| "all of these MRs must hold for the same `f`" | `metamon.forall_morphs` |

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
