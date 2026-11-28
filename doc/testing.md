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

## Coverage

`gleam run -m metamon/mutation -- coverage` (`just coverage`) runs the tests on the Erlang target with every module under `src/` measured and writes `build/coverage/lcov.info`; `.github/workflows/coverage.yml` reports it with octocov on pull requests and main.

## Mutation testing

`gleam run -m metamon/mutation` (`src/metamon/mutation.gleam`) mutates every module under `src/`, including itself: `==` and `!=` swapped, `<` and `<=`, `>` and `>=` moved across the boundary, `&&` and `||` swapped, `!` dropped, `True` and `False` swapped, and the arithmetic operators swapped, for integers and floats. `.github/workflows/mutation.yml` mutates the modules a pull request changes and fails on a survivor that `doc/mutation/baseline.json` does not list; the weekly run mutates every module. The score is (killed + timed out) / (killed + timed out + lived). `test/mutation_test.gleam` applies every mutant of every module here and checks that glance still parses the result.

<!-- mutation:start -->
| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `metamon` | 13 | 8 | 0 | 61.9% |
| `metamon/generator` | 24 | 24 | 0 | 50.0% |
| `metamon/internal/coverage` | 11 | 2 | 0 | 84.6% |
| `metamon/internal/diff` | 5 | 5 | 0 | 50.0% |
| `metamon/internal/edges` | 6 | 2 | 0 | 75.0% |
| `metamon/internal/interval` | 5 | 6 | 0 | 45.5% |
| `metamon/internal/mutant` | 8 | 0 | 0 | 100.0% |
| `metamon/internal/mutation` | 28 | 1 | 0 | 96.6% |
| `metamon/internal/regression` | 4 | 1 | 0 | 80.0% |
| `metamon/internal/report` | 3 | 0 | 0 | 100.0% |
| `metamon/internal/runner` | 16 | 13 | 0 | 55.2% |
| `metamon/internal/seed` | 16 | 10 | 1 | 63.0% |
| `metamon/internal/shrink` | 13 | 8 | 0 | 61.9% |
| all | 152 | 80 | 1 | 65.7% |
<!-- mutation:end -->

The first full run (2026-11-27) scored 65.0% with 82 survivors; 12 were in the mutation modules and tests now kill them, except `measure_unmutated`, whose elapsed time only sets the timeout. The other 69 survivors are recorded in the baseline as found: boundary comparisons and arithmetic in generators, sizes, seeds and float shrinking, the tolerance checks in `approximately`, and flags in the runner that only change how a report is laid out. They are the next tests to write. That run was on a machine with a load average above 150, and 10 mutants were counted as killed because an unrelated test failed under the load; the first run on CI (2026-11-27) found them alive, so the baseline lists them as survivors. One of them, `actual_pct` with `total < 0`, is equivalent, since dividing by 0.0 gives 0.0.
