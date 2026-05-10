# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.8.0] - 2026-05-10

### Tests

- New `test/config_boundary_test.gleam` module pins the validation
  contracts of every `with_*` config builder (`with_runs`,
  `with_max_size`, `with_shrink_limit`, `with_max_edges`,
  `with_regression_file`) and every `range` constructor
  (`singleton`, `constant`, `linear`, `linear_from`,
  `exponential`) for negative, zero, smallest-valid, very-large,
  inverted-bounds, and singleton-pair inputs. Centralising these
  cases in one module makes it obvious which builder × boundary
  pairs are pinned and prevents the per-builder leakage pattern
  that produced #35 and #52. (#83)
- New `test/json_schema_contract_test.gleam` module pins the JSON
  failure-report schema declared stable in README §JSON output.
  Triggers each public failure shape that emits JSON
  (`forall`, `forall_morph`, `forall_round_trip`) and asserts that
  every one of the 17 README-listed top-level keys is present, plus
  the documented value-type for `config_seed` / `runs_done` /
  `runs_total` / `shrinks_done` (Int), `shrink_capped` (Bool),
  `annotations` / `footnotes` (Array), and `coverage` (Object or
  null). Locks down the contract that downstream `jq` pipelines,
  GitHub Actions annotations, and LLM-driven analysis steps depend
  on. (#82)
- New `test/regression_robustness_test.gleam` module pins the
  deviation behaviour of `regression.parse` /
  `parse_with_version`: malformed TOML, truncated blocks,
  unknown future schema_version, malformed schema_version line,
  bad value types, missing required fields, CRLF line endings,
  UTF-8 BOM, large multi-block files, and duplicate keys in one
  block. Adds three PBT-style fuzz tests using metamon's own
  `string_printable_ascii` and `string_unicode` generators that
  assert "no panic" across 200 iterations each — the only public
  surface ingesting user-controlled file content gets the same
  fuzz discipline metamon applies to its other public surface.
  Companion to #58 (which pinned the format); #84 pins the
  format-deviation behaviour. (#84)

## [0.7.0] - 2026-05-11

### Documentation

- README adds a **"Case study: CRDT algebraic laws"** section between
  Stateful / model-based testing and Configuration. The case study
  shows how a single user-defined type (G-Counter) can be tested
  against three algebraic laws — idempotency, commutativity,
  associativity — using `metamon.forall`. Demonstrates the idiomatic
  fallback to `forall` when properties are n-ary equations that don't
  fit the unary `idempotency_of` / `commutativity_of` MR templates.
  The example pitches metamon as a natural fit for distributed-systems
  / state-replication library authors who reach for property-based
  testing first. The three test functions in the example are mirrored
  in `test/readme_test.gleam` so the sample cannot drift from the
  actual API. Table of contents updated to link the new section. (#79)

## [0.6.0] - 2026-05-09

### Documentation

- README's `## Round-trip variants` section now opens with a short
  "Tip — encoder / decoder libraries" callout that shows the canonical
  starter property for any package that owns a paired `encode` /
  `decode`. The callout is intentionally a copy-pasteable
  `forall_round_trip` snippet so codec authors see the recipe before
  diving into the partial / custom-equality variants. (#75)

### Added

- Property-based self-tests in
  `test/metamon_self_property_test.gleam` that exercise `transform`,
  `relation`, and `generator` laws against metamon-generated inputs
  rather than the point fixtures the existing per-feature test files
  use. Highlights: `transform.then` is associative with `identity` as
  a two-sided neutral and `repeat(t, n)` equals n compositions;
  `relation.and` / `or` / `invert` match the corresponding boolean
  operations and `invert ∘ invert == identity`; `relation.equal` is
  reflexive and symmetric; `relation.permutation_of` and
  `subset_of` hold on every list compared with itself and on the
  reverse pair; `generator.non_negative_int` / `positive_int` /
  `negative_int` / `byte` produce values in their documented ranges;
  `generator.list_of(_, range.constant(0, n))` produces lists of
  length in `[0, n]` and `non_empty_list_of` always produces at
  least one element.

## [0.5.0] - 2026-05-07

### Fixed
- `metamon.forall_morphs([], ...)` and `metamon.forall_morph_n` /
  `forall_morph_n_with` with an empty `transforms` list no longer pass
  vacuously. The runner panics with a structured "empty MR list /
  empty transforms list (vacuous test)" message that points users at
  `forall(...)` for the no-MR case. This matches the existing
  empty-list rejection in `frequency` / `one_of` / `element_of`. (#50)
- `metamon/stateful.run(model, real, [])` no longer returns
  `Passed(ran: 0, skipped: 0)` silently. The function panics with a
  structured "empty commands list (vacuous test)" message that points
  users at `forall(...)` for the non-stateful case. The companion
  `assert_passed` panics with the same message when handed an
  `Outcome` with `ran == 0 && skipped == 0`, so a vacuous outcome
  produced by other means still surfaces. Companion to #50. (#54)
- `metamon/stateful.assert_passed` panics when handed an `Outcome`
  with `ran == 0 && skipped > 0` — i.e. every command's
  `precondition` returned `False` for the model the runner walked.
  The message names the API and the skipped count and asks the
  caller to adjust preconditions or the initial model so at least
  one command fires; silently passing previously hid precondition /
  initial-model bugs (model never advanced, `precondition` always
  returned `False`, etc.). Companion to #54. (#55)
- `metamon/coverage.cover` validates `target_pct` at the call site
  and panics with `"metamon.coverage.cover: target_pct must be in
  [0.0, 100.0] (got <value>)"` for values outside that range or for
  `NaN`. Out-of-range targets previously slid through and turned a
  copy-paste typo (`50.0` → `500.0`) into a confusing coverage
  shortfall on every run. The companion `cover_at_least` rejects
  negative `min_hits` with a similar structured message. Same
  "fail visibly on misconfiguration" stance as `relation.approximately`
  (#34) and `Range.linear_from` (#35). (#52)

### Changed
- **Breaking:** `generator.frequency` now panics with a structured
  message (`"metamon.frequency: weight must be >= 1 (got <w> at
  position <n>)"`) when any pair carries a weight of `0` or a
  negative weight. The previous behaviour silently coerced
  `weight < 1` to `1`, so `frequency([(0, gen_a), (1, gen_b)])`
  was a 50/50 split rather than the intended "always pick `gen_b`",
  and a `weight = max(0, computed)` defensive pattern lost its
  safety net. Test authors who used `weight = 0` to keep a
  placeholder slot must now drop the entry instead. (#48)

### Added
- Regression-file format gains a `schema_version = 1` header line.
  Newly written files always carry the header; legacy v0 files
  (without the header) are still accepted by the parser. A future
  schema bump (v2+) is rejected with a structured `ParseError`
  (`UnsupportedSchemaVersion` / `MalformedSchemaVersion`) returned
  from a new `regression.parse_with_version/1`. The lenient
  `regression.parse/1` used by the runner returns `[]` (skip replay)
  on version mismatch instead of aborting the run, so a stale
  checked-in regression file from a newer metamon does not break a
  downgrade. The schema is documented in the
  `metamon/internal/regression` module docstring; the
  `with_regression_file` config builder docstring points at it and
  spells out the concurrency contract (each call reads-appends-writes
  the file, so parallel workers should split paths). (#58)
- `generator.map7`, `generator.map8`, `generator.tuple6`,
  `generator.tuple7`, and `generator.tuple8` extend the existing
  applicative-map / tupling family up to arity eight. Records with
  six to eight fields (HTTP `Request`, multipart `Part`, OpenAPI
  `Operation`, etc.) can now be built with a single applicative
  composition that preserves integrated shrinking, instead of the
  `bind`-based workaround whose shallow-shrinking caveat is
  documented in the Limitations section. Stops at eight because
  arity nine is comfortably above every record in the audited
  workload; reach for nested `map2` / `bind` (and accept the caveat)
  for higher arities. (#57)
- `metamon.forall_round_trip_partial` and
  `forall_round_trip_partial_with` now register an automatic
  `coverage.cover_at_least(1, "encoder_accepted", ...)` requirement
  for each input. When the user's encoder rejects every input the
  generator produces, the runner panics with a structured "coverage
  shortfall" message naming the `encoder_accepted` label, instead of
  passing silently as `100 / 100`. This catches the #28 follow-up
  foot-gun (a generator-vs-encoder mismatch produces a green test
  with zero round-trips actually exercised). Callers who need a
  stricter floor (e.g. "≥ 50% of inputs must round-trip") can stack
  a `coverage.cover(50.0, "encoder_accepted", ...)` call inside their
  own property body — coverage labels accumulate. (#49)
- `command.no_precondition` is a clearer-named synonym for
  `command.always`. The "no precondition" reading matches the
  constructor's actual contract (the precondition arm is `fn(_m) {
  True }`); "always" reads as "always runs", which overstates the
  guarantee — the command's `run` step can still return `Error`,
  halting the sequence. `command.always` is kept as a non-deprecated
  alias so existing call sites continue to compile. Prefer
  `no_precondition` in new code. (#56)
- `relation.set_subset_of()` is a set-semantics counterpart to
  `relation.subset_of()` (which is multiset). `set_subset_of([1, 1],
  [1])` is `True`; `subset_of([1, 1], [1])` remains `False`. The
  multiset version's docstring is rewritten to make the multiset
  contract explicit and to point at `set_subset_of` for the
  alternative; the README modules table tags both with `(multiset)`
  / `(set)` so readers don't have to guess. Reach for `set_subset_of`
  on header-style lists where presence matters but count does not;
  reach for `subset_of` (multiset) when matching with multiplicity is
  the intent. (#53)
- `generator.float_special()` and `generator.float_special_edges()`
  expose the IEEE 754 special-value edges that the regular
  `generator.float(lo, hi)` never emits: `NaN`, `+Infinity`,
  `-Infinity`, the smallest positive denormal, the largest finite
  double, and the anchors `0.0`, `-0.0`, `1.0`. Codec / serialisation
  properties that need to exercise these edges (`NaN != NaN`
  breaking round-trips, `Infinity` formatting issues, `-0.0`
  round-trip drift) can use the new generator directly or splice
  `float_special_edges()` into an existing range generator via
  `with_examples`. The `float/2` docstring now states explicitly
  that it is finite-only and points at `float_special` for IEEE
  edges.

  Target asymmetry: on JavaScript the non-finite slots return
  genuine `NaN` / `±Infinity` via `Number.{NaN, POSITIVE_INFINITY,
  NEGATIVE_INFINITY}`. On the BEAM they return finite sentinels
  (largest finite double, signed for `-Infinity`) because the
  standard `<<F/float>>` pattern, `binary_to_term/1` with
  NEW_FLOAT_EXT, and `binary_to_float/1` all reject non-finite IEEE
  754 bit patterns — there is no portable way to construct NaN /
  ±Infinity from pure Erlang. Properties that strictly require
  genuine non-finite inputs must run on the JavaScript target.
  (#51)

### Documentation
- `generator.unicode_codepoint` and `generator.string_unicode`
  docstrings now spell out the surrogate exclusion: lone surrogates
  (`0xD800–0xDFFF`) and other malformed UTF-8 byte sequences are not
  reachable through these generators because Gleam strings are UTF-8.
  A parser-hardening property that must accept or reject malformed
  UTF-8 input has to drop down to `bit_array(byte_len)` and operate
  at the byte level. The docstrings also note the absence of a
  built-in NFC-vs-NFD normalisation bias — equivalent codepoint
  sequences (`"é"` as `U+00E9` vs `U+0065 U+0301`) are sampled
  independently. README §3.0 carries the same note in one paragraph.
  (#59)
- `metamon.seed/1` (and the underlying `metamon/generator/seed.seed`)
  docstring now describes the full normalisation: the integer is
  masked to a 32-bit non-negative window, and a masked-to-zero value
  is silently replaced with `0xDEADBEEF` because the xorshift family
  has `0` as a fixed point. Failure-report headers annotate the
  canonical state with the original input when normalisation kicked
  in (e.g. `config seed: 3735928559 (originally seed(0))`), so a
  user who pins `seed(0)` in source can map the report back to that
  source line. The seed module also exposes a new `original_input/1`
  accessor returning `Option(Int)` for downstream tools that want
  the user-visible value. The JSON failure report gains a matching
  `config_seed_original` field. (#47)

## [0.4.0] - 2026-05-07

### Documentation
- README §2.2.1 (new) walks through round-trip recipes for codecs
  whose `encode` / `decode` types don't line up with the
  `forall_round_trip` happy path: partial encoders
  (`forall_round_trip_partial`) and source types whose decoded form
  needs a custom equality (`forall_round_trip_under`). Both snippets
  are exercised by `gleam test` via `test/readme_test.gleam` and
  cannot drift out of sync with the API. (#32)
- README *Limitations* section restructured: each caveat now carries
  an explicit **What you'll observe** narrative and a
  **Workaround** entry, and the section gains coverage of two
  caveats that previously had no doc anchor: `generator.filter` panics
  after 100 consecutive rejections, and `with_examples` accumulates
  without deduplication. The five existing caveats (`Transform(a)`
  type, `Relation(b)` arity, `bind` shrink shallowness, `recursive`
  branch-swap, JS parallel runner state) were rewritten in the same
  format. (#36)

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
