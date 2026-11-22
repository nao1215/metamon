# Testing

`gleam test` runs everything below except the nightly job. CI runs it on the Erlang target (Gleam floor and latest 1.x, several OTP versions) and on the JavaScript target (several Node versions).

## Examples and unit tests

Each area has a test file with fixed inputs and expected outputs: generators and their edges (`generator_test.gleam`, `characters_test.gleam`, `edges_in_range_test.gleam`, `edge_propagation_test.gleam`, `string_edges_test.gleam`, `range_test.gleam`, `max_size_test.gleam`), shrinking (`forall_shrink_test.gleam`, `list_shrink_test.gleam`, `shrink_strategy_test.gleam`, `tree_test.gleam`), relations (`relation_test.gleam`), configuration (`config_test.gleam`), panicking properties (`panic_property_test.gleam`), coverage and annotations (`coverage_test.gleam`, `coverage_denominator_test.gleam`, `annotate_test.gleam`, `annotate_order_test.gleam`), the failure report (`runner_failure_test.gleam`, `report_diff_test.gleam`) and regression files (`regression_test.gleam`, `regression_runner_test.gleam`). `readme_test.gleam` runs every README example.

## Generated properties

metamon tests itself with metamon. `metamon_self_property_test.gleam` runs properties over transforms, relations and generators; `generator_algebra_test.gleam` checks the functor, applicative and monad laws of `Generator`; `regression_robustness_test.gleam` feeds generated text to the regression-file parser.

## Metamorphic relations

`morph_test.gleam`, `morph_pipeline_test.gleam` and `commutativity_test.gleam` check `forall_morph` and the relation templates on functions whose relations are known, and check that each one fails with a report when the relation is broken.

## Contracts

`json_schema_contract_test.gleam` pins the keys and types of the JSON failure report, and `json_output_test.gleam` checks its content. `perf_smoke_test.gleam` fails when 1000 runs of a non-trivial property exceed a generous time budget, which catches quadratic shrink expansion.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `Config(..default_config(), seed: Some(seed))` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time (`==`/`!=`, `&&`/`||`, float comparisons, `-.`/`+.`, `-> True`/`-> False`, a dropped `!`) and runs `gleam test` on the Erlang target. The score is killed / (killed + lived).

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19 | every module under `src/` | 68 | 9 | 88.3% |

The first run scored 58/77 (75.3%). No test checked that `generator.float(lo, hi)` stays in `[lo, hi]` when `lo` is not 0, that float edges drop the anchors outside the range and keep both bounds, that edges are deduplicated, that `non_empty_list_of` drops the empty list when its range admits length 0, or that `range.linear` picks 0 as its origin only when 0 is in range. Tests for each now exist.

The 9 remaining survivors are kept as found, not relabelled: the vacuous-pass branches of `forall_round_trip_partial_with` and `forall_round_trip_under_with` (2), which only record coverage; `attach_known_root` (1), whose fallback branch is unreachable because `tree.unfold` already puts the value at the root; `diff.build_row`, `is_list_inspect` and `is_tuple_inspect` (3), which only change how a failure report lays out a diff; a negation in the runner's `shrink_loop` (1); and boundary comparisons in `relation.approximately` and `coverage.shortfalls` (2).
