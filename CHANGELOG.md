# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Documentation
- README §2.2.1 (new) walks through round-trip recipes for codecs
  whose `encode` / `decode` types don't line up with the
  `forall_round_trip` happy path: partial encoders
  (`forall_round_trip_partial`) and source types whose decoded form
  needs a custom equality (`forall_round_trip_under`). Both snippets
  are exercised by `gleam test` via `test/readme_test.gleam` and
  cannot drift out of sync with the API. (#32)

### Added
- `generator.bit_array_unaligned(bit_len)` produces a `BitArray` whose
  total length in bits is in the configured range and may be sub-byte
  (i.e. not a multiple of 8). Use it to fuzz code paths that take an
  arbitrary `BitArray`: codec internals, length-prefixed framing,
  bignum bit walks, and parsers that must reject (or handle) sub-byte
  tails. The byte-aligned `bit_array(byte_len)` remains the right
  default for byte-oriented properties. (#31)
- `metamon.forall_round_trip_under` and
  `forall_round_trip_under_with` accept a caller-supplied
  `Relation(a)` instead of structural `==` for the round-trip
  comparison. Use this when the source type has an opaque or
  normalising shape (multipart `Part` with re-derived caches, MIME
  types whose essence lowercases, etc.). Compose with
  `relation.equivalent_under(via, name)` to compare on a projection.
  (#29)
- `metamon.forall_round_trip_partial` and
  `forall_round_trip_partial_with` for codecs whose encoder is partial
  (`encode: fn(a) -> Result(b, e)`). Inputs the encoder rejects with
  `Error(_)` are treated as out of scope and skipped — the property is
  vacuously satisfied for them. Use this when wrapping codecs with
  structural preconditions (byte-alignment requirements, value-range
  checks, hrp / version constraints) without the boilerplate
  `let assert Ok(s) = encode(...)` shim. (#28)

### Changed
- **Breaking:** `relation.approximately(epsilon)` now panics at
  construction when `epsilon < 0.0`. The previous behaviour silently
  produced a degenerate "always false" relation that broke reflexivity
  (a value was no longer "approximately equal" to itself), which is
  almost always a sign mistake on the caller's part. Failing visibly
  matches the project's posture for malformed numeric inputs in
  `Range.constant` / `Range.linear`. (#34)
- **Breaking:** `Range.linear_from(origin, lo, hi)` now panics at
  construction when `origin` lies outside `[lo, hi]`. The previous
  behaviour silently emitted `origin` (and only `origin`) at small
  sizes — for `linear_from(100, 0, 10)`, every value generated at
  `size = 0` was `100`, outside the documented `[0, 10]` interval.
  This matched neither `Range.linear`'s automatic in-bounds origin
  selection nor the `Range` contract that values stay inside the
  configured interval. Failing visibly catches the misuse early. (#35)
- **Breaking:** `generator.string_ascii(len)` now samples the full
  ASCII range (`0x00`..`0x7F`) at random, including control bytes
  (`0x00`..`0x1F`, `0x7F`). Previously the random sampler used
  `ascii_printable` (`0x20`..`0x7E`) and control characters were
  reachable only via curated edges — properties fuzzing parsers that
  must handle control bytes never explored those branches. Reach for
  `string_printable_ascii` if your property depends on printable-only
  input. (#33)
- **Breaking:** parameter renames on the BitArray generators to
  disambiguate the unit:
  - `generator.bit_array(len)` → `generator.bit_array(byte_len)`
  - `generator.bit_array_printable(len)` → `generator.bit_array_printable(byte_len)`
  - `generator.bit_array_utf8(len)` → `generator.bit_array_utf8(codepoint_len)`
  Positional callers are unaffected; only call sites that used the
  labelled form (`bit_array(len: ...)`) need updating. The new names
  make the unit obvious at the call site. (#30)

## [0.3.0] - 2026-05-06

### Added
- `metamon.forall_round_trip` and `metamon.forall_round_trip_with`
  runners for the `decode(encode(x)) == Ok(x)` shape. Failure reports
  include the header `round_trip[<name>]` so the panic message
  identifies which round-trip broke; the underlying machinery is the
  same as `forall`, including shrinking of the source input. (#18)
- `metamon.forall_observable` and `metamon.forall_observable_with`
  runners. The predicate returns `#(observation, holds)`; the
  observation is rendered into the failure report under the label
  `predicate value`, removing the manual
  `annotate.annotate_value` instrumentation step that asymmetric
  with `forall_morph`'s built-in source/follow-up rendering. (#17)
- `generator.element_of(values)` — shortcut for
  `one_of(list.map(values, return))`. Panics on an empty list,
  mirroring `one_of([])`. Every value becomes an edge. (#16)
- Character-class string shortcuts: `generator.string_alpha`,
  `string_alphanumeric`, `string_digit`, and
  `string_printable_ascii`. The last differs from `string_ascii` by
  skipping the curated edge cases that include `\t` and `\n`. (#15)
- `BitArray` generator shortcuts: `generator.bit_array_printable`
  (every byte in `0x20`..`0x7E`) and `generator.bit_array_utf8`
  (`len` is the codepoint count, not the byte count). (#15)

### Documentation
- README §4.2 now documents the four domain-specific relation
  combinators with worked examples: `relation.approximately`,
  `permutation_of`, `subset_of`, `monotone`. (#19)
- README §2.2 (round-trip) rewritten on top of `forall_round_trip`;
  the older two `forall`-based round-trip examples are removed in
  favour of the named-header runner. (#18)
- README §1.1 (new) walks through `forall_observable` for properties
  whose branch hinges on an intermediate value. (#17)
- README §3.0 shortcut catalog extended with the new string and
  bit_array generators; existing `ascii_*` family cross-referenced
  for single-character generators. (#15)
- README §Install gets a new "Dependency footprint" subsection
  explaining when `simplifile` and `gleam_json` are reached and the
  trade-off behind metamon's single-package shape. (#20)

## [0.2.0] - 2026-05-06

### Fixed
- `generator.string`, `generator.string_ascii`, `generator.string_unicode`,
  and `generator.list_of` now filter their curated edge values by the
  user-supplied length `Range`. Previously, edges were appended
  unconditionally, so `string_ascii(range.constant(5, 8))` emitted `""`,
  `" "`, `"OAuth2Token"` (length 11) and other lengths outside the
  documented window — a property assuming `5 <= len(s) <= 8` could fail
  spuriously on the very first edge run. The string variants additionally
  dedupe their per-layer edge list (`""` no longer appears multiple
  times within a single source). (#3)

### Added
- `metamon.with_runs_or_panic`, `with_max_size_or_panic`,
  `with_shrink_limit_or_panic`, `with_max_edges_or_panic`, and
  `with_regression_file_or_panic` panic-on-error variants of the
  validating config builders. Use in test code where the bound is a
  literal and the `let assert Ok(c) = ...` arm is dead code; the
  validating variants are still the right choice when the value
  comes from disk, env vars, or a CLI flag. The panic message
  carries the structured `ConfigError` so misuse is still legible.
  (#6)

### Changed
- **BREAKING** `metamon/generator/range`: `range.constant`, `range.linear`,
  `range.linear_from`, and `range.exponential` now panic at construction
  when `lo > hi` instead of silently swapping the bounds. An inverted pair
  is almost always a bug (swapped arguments), so failing visibly catches
  it earlier than a normalisation that the README never documented. Match
  metamon's existing "fail visibly on misconfiguration" stance (`with_runs(0)`
  errors, `filter` panics when the predicate rejects everything). (#7)
- **BREAKING** `metamon.commutativity_of` no longer takes the `of:` parameter.
  The argument was never read by the body — the swap transform and structural
  equality are independent of the supplied function — and forced callers to
  thread the operator twice (once into the template, once into `forall_morph`).
  Drop `of:` at the call site:
  ```gleam
  // before
  let mr = metamon.commutativity_of(name: "add_commutative", of: add)
  // after
  let mr = metamon.commutativity_of(name: "add_commutative")
  ```
  (#5)

## [0.1.0] - 2026-05-06

Initial public release.

### Added

#### Property-based testing
- `metamon.forall` / `metamon.forall_with` — single-input predicate
  search with deterministic seeding.
- `metamon/generator` — opaque `Generator(a)` with full applicative
  combinators (`map`, `bind`, `map2`..`map6`, `tuple2`..`tuple5`,
  `one_of`, `frequency`, `sized`, `resize`, `scale`, `filter`,
  `recursive`).
- Standard generators: `int(Range)`, `float`, `bool`,
  `non_negative_int`, `positive_int`, `negative_int`, `byte`,
  `bit_array`, `ascii_*`, `unicode_codepoint`, `string*`, `list_of`,
  `non_empty_list_of`, `dict_of`, `set_of`, `option_of`, `result_of`.
- Edge values: every standard generator carries a curated boundary
  set that the runner consumes before random sampling. Users add
  their own with `with_examples` / `add_edges`.
- Range-based size scaling: `singleton`, `constant`, `linear`,
  `linear_from`, `exponential` (Hedgehog-style).

#### Metamorphic testing
- `metamon.forall_morph` / `forall_morph_with` / `forall_morphs` —
  binary metamorphic relations.
- `metamon.forall_morph_n` / `forall_morph_n_with` —
  N-ary metamorphic relations across many follow-up outputs.
- `metamon.assert_morph` — single-input MR for regression tests.
- MR templates: `idempotency_of`, `invariant_under`,
  `equivariant_under`, `commutativity_of`.
- `metamon/transform` (with `list` / `string` / `dict` sub-modules):
  named, deterministic input transforms with `then`, `repeat`,
  `rename`, `constant`.
- `metamon/relation`: named binary predicates (`equal`, `not_equal`,
  `equivalent_under`, `approximately`, `permutation_of`,
  `subset_of`, `monotone`, `implies`, `and`, `or`, `invert`) and
  N-ary relations (`RelationN`, `all_equal`, `pairwise`).

#### Stateful / model-based testing
- `metamon/command` — `Command(model, real)` type and constructors.
- `metamon/stateful` — `run(initial_model, initial_real, commands)`
  with `Outcome(model)` (`Passed` / `Failed`) and `assert_passed`.

#### Failure reporting
- Multi-line text output with shrunk source/follow-up inputs and
  outputs, structural diff, transform/relation names, configured
  seed, and a paste-ready `assert_morph` reproduce block.
- Single-line JSON output via
  `metamon.with_output_format(config.Json)` with a stable schema
  for CI dashboards and LLM analysis.
- `metamon/diff` — structural diff (`Same`/`Differ`/`ListDiff`/
  `TupleDiff`/`StringDiff`) used by the failure formatter.
- `metamon/annotate` — `annotate`, `annotate_value`, `footnote` for
  per-property context that is invisible on success and shown on
  failure.

#### Coverage
- `metamon/coverage` — `classify`, `cover` (percentage),
  `cover_at_least` (absolute count), `classify_in_bucket` (mutually
  exclusive grouping), `collect`. Coverage shortfalls fail the
  property even when every individual run passed.

#### Configuration & determinism
- xorshift32 PRNG (`metamon/generator/seed`) with `split` for
  bit-identical streams on BEAM and JavaScript targets.
- `metamon/config`: opaque `Config` with `with_runs`, `with_seed`,
  `with_max_size`, `with_shrink_limit`, `with_max_edges`,
  `with_regression_file`, `with_diff_enabled`, `with_output_format`.
  Validators return `Result(Config, ConfigError)` instead of
  silently falling back to defaults.

#### Regression file
- `metamon.with_regression_file(path)` — failures are appended to a
  TOML log keyed by `(seed, run_index, size, edge_index)` and
  replayed at the start of subsequent runs before any random
  generation.

### Notes

- Runtime dependencies: `gleam_stdlib`, `gleam_json`, `simplifile`.
  No external property-based testing library is wrapped; everything
  (`Seed`, `Tree`, `Range`, `Generator`, shrink, runner) is
  implemented inside metamon.
- Targets: Erlang/OTP 27 and 28 on BEAM; Node 22 and 24 on
  JavaScript. CI runs both matrices on every push.
- See `Limitations` in the README for known scope cuts (no
  type-changing input transforms, no heterogeneous relations,
  shallow `bind` / `recursive` shrinks).

[0.1.0]: https://github.com/nao1215/metamon/releases/tag/v0.1.0
