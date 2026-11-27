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
gleam run -m metamon/mutation -- run [--workers N] [--exclude FILE]... [FILE]...
gleam run -m metamon/mutation -- list [--exclude FILE]... [FILE]...
gleam run -m metamon/mutation -- baseline
gleam run -m metamon/mutation -- gate
gleam run -m metamon/mutation -- doc-check
```

- `run` mutates the given modules, or every module, in `N` copies of the project (default 4) and writes `build/mutation/results.json`. `--exclude` leaves a module out, such as a generated table.
- `list` prints the mutants without running them.
- `baseline` copies a run over every module that was not excluded to `doc/mutation/baseline.json`. When `doc/testing.md` has `<!-- mutation:start -->` and `<!-- mutation:end -->`, it also writes the table of killed and lived mutants per module between them.
- `gate` exits with 1 when a mutant lives that the baseline does not list.
- `doc-check` exits with 1 when the table in `doc/testing.md` does not match the baseline.

The score is (killed + timed out) / (killed + timed out + lived); a mutant that does not compile is not counted.

## Survivors and the gate

Some survivors cannot be killed, because the change gives the same output (`x < 0` and `x <= 0` where `x` is never 0). Recording them in the baseline lets a pull request mutate only the modules it changes and still fail on a new survivor. A survivor is matched by module, function, mutator, line text and its column in that text, so moving code to another line does not make it new.

A survivor is run two more times and counts only when it lives every time, because property tests draw new inputs on each run. Each mutant may run for four times as long as the tests take without a mutation, and at least a minute; one that runs longer counts as killed.

Each test run has `+hmax 134217728 +hmaxib true` added to `ERL_ZFLAGS`, so a process that grows past 1 GiB, binaries included, is killed and the mutant counts as killed. Without the limit, a mutant that makes a test allocate without end can fill the memory of a CI runner before the timeout ends it. If a test needs more than 1 GiB in one process, the run without a mutation fails and the output says so.

## On pull requests

[`.github/workflows/mutation.yml`](https://github.com/nao1215/metamon/blob/main/.github/workflows/mutation.yml) in this repository mutates the modules a pull request or push changes, runs `gate`, and mutates every module once a week. It can be copied as is.
