# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
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
