set shell := ["bash", "-cu"]

default:
  @just --list

deps:
  gleam deps download

format:
  gleam format

format-check:
  gleam format --check .

typecheck:
  gleam check

lint:
  gleam run -m glinter

build:
  gleam build --warnings-as-errors

test:
  gleam test

docs:
  gleam docs build

check:
  gleam format --check .
  gleam run -m glinter
  gleam check
  gleam build --warnings-as-errors
  gleam test

# Mutation testing of every module, failing on survivors the baseline lacks.
# Slow: run it on a machine with many cores, then `just mutation-record`.
mutation workers="8":
  gleam run -m metamon/mutation -- run --workers {{workers}}
  gleam run -m metamon/mutation -- gate

# Record the last full mutation run as the baseline and refresh doc/testing.md
mutation-record:
  gleam run -m metamon/mutation -- baseline

# Line coverage of the Erlang test run, written to build/coverage/lcov.info
coverage:
  gleam run -m metamon/mutation -- coverage

all: deps check

clean:
  gleam clean
