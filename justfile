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

ci: deps check

clean:
  gleam clean
