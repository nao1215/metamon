# Mutation testing

`gleam run -m metamon/mutation` changes one operator, `!` or boolean literal in a module under `src/` at a time and runs `gleam test --target erlang` in a copy of the project. A mutant the tests still pass with has survived: the behaviour it changed is not checked by any test.

Add metamon as a dev dependency and run it from the project root. It runs on the Erlang target and needs `timeout` from GNU coreutils (`gtimeout` on macOS).

## What changes

- `==` and `!=` swapped, `<` and `<=`, `>` and `>=` moved across the boundary, for integers and floats
- `&&` and `||` swapped, `!` dropped, `True` and `False` swapped
- `+` and `-` swapped, `*` and `/` swapped, `%` changed to `*`, for integers and floats

Pipes, string concatenation, patterns, strings and bit array options are left alone.

## Commands

```sh
gleam run -m metamon/mutation -- run [--workers N] [--shard K/N] [--exclude FILE]... [FILE]...
gleam run -m metamon/mutation -- list [--shard K/N] [--exclude FILE]... [FILE]...
gleam run -m metamon/mutation -- merge FILE...
gleam run -m metamon/mutation -- baseline
gleam run -m metamon/mutation -- gate
gleam run -m metamon/mutation -- doc-check
gleam run -m metamon/mutation -- coverage
```

- `run` mutates the given modules, or every module, in `N` copies of the project (default 4) and writes `build/mutation/results.json`. `--exclude` leaves a module out, such as a generated table.
- `--shard K/N` runs part `K` of `N`: every `N`-th mutant, starting at the `K`-th.
- `list` prints the mutants without running them.
- `merge` joins the results files of parts 1 to `N` of one run into `build/mutation/results.json`, so that `gate` and `baseline` can use them. It fails when a part is missing or appears twice, or when the files come from different modules.
- `baseline` copies a run over every module that was not excluded to `doc/mutation/baseline.json`. When `doc/testing.md` has `<!-- mutation:start -->` and `<!-- mutation:end -->`, it also writes the table of killed and lived mutants per module between them.
- `gate` exits with 1 when a mutant lives that the baseline does not list.
- `doc-check` exits with 1 when the table in `doc/testing.md` does not match the baseline.
- `coverage` runs the tests with every module under `src/` measured and writes the lines they reach to `build/coverage/lcov.info`. See [Line coverage](#line-coverage).

The score is (killed + timed out) / (killed + timed out + lived); a mutant that does not compile is not counted.

## Survivors and the gate

Some survivors cannot be killed, because the change gives the same output (`x < 0` and `x <= 0` where `x` is never 0). Recording them in the baseline lets a pull request mutate only the modules it changes and still fail on a new survivor. A survivor is matched by module, function, mutator, line text and its column in that text, so moving code to another line does not make it new.

A survivor is run two more times and counts only when it lives every time, because property tests draw new inputs on each run. Each mutant may run for four times as long as the tests take without a mutation, and at least a minute; one that runs longer counts as killed.

Each copy is compiled with `gleam build` first, and then the test run has `+hmax 33554432 +hmaxib true` added to `ERL_ZFLAGS`, so a process that grows past 256 MiB, binaries included, is killed and the mutant counts as killed. Without the limit, a mutant that makes a test allocate without end can fill the memory of a CI runner before the timeout ends it. A test process that recurses without end still grows to about 3.5 GB before the kill. The compiler runs without the limit, because it needs more than 256 MiB for a large module. If a test needs more than 256 MiB in one process, the run without a mutation fails and the output says so.

## Line coverage

A mutant on a line that no test reaches always survives, so line coverage shows where the survivors will be before a long run. `coverage` builds the project with `gleam build --target erlang` and measures it with Erlang's `cover` in a fresh `erl`: it measures every module under `src/`, starts the package's applications and runs every module under `test/` with eunit as `gleam test` does, and writes `build/coverage/lcov.info`. It exits with 1 when a test fails, and with 2, leaving `lcov.info` as it was, when the measuring fails. A module that `cover` cannot measure is named on standard error. The line numbers are those of the Gleam source, so the file works with any tool that reads LCOV, such as [octocov](https://github.com/k1LoW/octocov):

```yaml
# .octocov.yml
coverage:
  paths:
    - build/coverage/lcov.info
```

It needs Gleam 1.19 or later: older compilers wrote Erlang source, and `cover` reported the lines of that source instead. Only the Erlang target is measured. Code that runs only on JavaScript, an `@external` function's Erlang or JavaScript module, and a program that a test starts in another process, such as an escript run by an end-to-end test, are not counted. The line that declares a function with an Erlang `@external` is left out, because a call to it goes straight to the Erlang function.

Measured code runs several times slower, so each test gets 500 seconds instead of the 50 that `gleam test` gives it.

## On pull requests

[`.github/workflows/mutation.yml`](https://github.com/nao1215/metamon/blob/main/.github/workflows/mutation.yml) in this repository mutates the modules a pull request or push changes, runs `gate`, and mutates every module once a week. It can be copied as is.

## Splitting a long run

A project with thousands of mutants can take longer than a CI job may run. Split the weekly run over a matrix with `--shard` and join the parts in one more job:

```yaml
jobs:
  part:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    strategy:
      fail-fast: false
      matrix:
        part: [1, 2, 3, 4]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: erlef/setup-beam@54075bcc5e249e4758d363f27d099f55d843f124 # v1.24.1
        with:
          otp-version: "29"
          gleam-version: "1.x"
      - run: gleam run -m metamon/mutation -- run --workers 4 --shard ${{ matrix.part }}/4
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: mutation-${{ matrix.part }}
          path: build/mutation/results.json
  merge:
    needs: part
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: erlef/setup-beam@54075bcc5e249e4758d363f27d099f55d843f124 # v1.24.1
        with:
          otp-version: "29"
          gleam-version: "1.x"
      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
        with:
          pattern: mutation-*
          path: parts
      - run: gleam run -m metamon/mutation -- merge parts/*/results.json
      - run: gleam run -m metamon/mutation -- gate
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: mutation-results
          path: build/mutation/results.json
```

Each part gets a share of every module, so the parts take about the same time. To record a new baseline from CI, download `mutation-results` to `build/mutation/results.json` and run `baseline`. A machine under heavy load can fail an unrelated test and count a mutant as killed, so a baseline made on CI is the more reliable one.
