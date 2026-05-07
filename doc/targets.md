# Targets and dependencies

## Supported targets

- Erlang (BEAM): full surface, used for everyday Gleam tests.
- JavaScript: the Generator / Tree / Seed core is pure Gleam (32-bit
  xorshift PRNG, no 64-bit arithmetic) and produces bit-identical
  output across both targets. `metamon/annotate` and `metamon/coverage`
  rely on a thin FFI shim for per-process state; the JS shim uses a
  module-level `Map`, so the runner clears it between properties.

## Runtime requirements

- Gleam 1.15 or later.
- Erlang/OTP 27 or later (when targeting Erlang; CI covers OTP 27 and 28).
- Node.js 22 or later (when targeting JavaScript; CI covers Node 22 and 24).

Node.js 18 reached end-of-life in April 2025 and Node.js 20 reached
end-of-life in April 2026. Node 22 is the current minimum.

## Dependency footprint

metamon ships as a single package and has three runtime dependencies:

- `gleam_stdlib` — required, used everywhere.
- `simplifile` — only reached through `metamon.with_regression_file`
  (the TOML regression-replay feature). If you never call
  `with_regression_file`, the runtime cost is just the resolve step.
- `gleam_json` — only reached through
  `metamon.with_output_format(config.Json)` (the JSON failure-report
  format used by CI / LLM consumers). Same story: never called means
  no runtime overhead, only a transitive entry in the dep graph.

If you need a leaner test-only dep set, `gleam_qcheck` ships with
`gleam_stdlib` alone and may be a better fit. metamon's design choice
is the single-package install experience (`gleam add metamon --dev`
and that's the whole story) over a multi-package split (`metamon`
core / `metamon_persistence` / `metamon_json`); both options were
considered. See
[#20](https://github.com/nao1215/metamon/issues/20) for the
discussion.

## Behavioural differences between targets

For known target-specific caveats — including parallel-runner state
leaks on JavaScript and float special-value behaviour on the BEAM —
see [doc/limitations.md](limitations.md).
