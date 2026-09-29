//// METAMON_RUNS_MULTIPLIER lets a nightly job run every property many
//// more times without editing a test.

import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range

const var = "METAMON_RUNS_MULTIPLIER"

fn run_counting(runs: Int) -> Int {
  let cfg = metamon.default_config() |> metamon.with_runs_or_panic(runs)
  count_reset()
  metamon.forall_with(cfg, generator.int(range.constant(0, 1000)), fn(_) {
    count_bump()
    True
  })
  count_get()
}

pub fn runs_are_multiplied_by_the_variable_test() {
  set_env(var, "3")
  let calls = run_counting(20)
  unset_env(var)
  calls |> should.equal(60)
}

pub fn runs_are_unchanged_without_the_variable_test() {
  unset_env(var)
  run_counting(20) |> should.equal(20)
}

pub fn an_invalid_multiplier_stops_the_run_test() {
  ["0", "-2", "many", ""]
  |> list_each(fn(value) {
    set_env(var, value)
    let #(panicked, message) = capture_panic(fn() { run_counting(5) })
    unset_env(var)
    #(value, panicked, string.contains(message, var))
    |> should.equal(#(value, True, True))
  })
}

fn list_each(items: List(a), f: fn(a) -> Nil) -> Nil {
  case items {
    [] -> Nil
    [first, ..rest] -> {
      f(first)
      list_each(rest, f)
    }
  }
}

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> a) -> #(Bool, String)

@external(erlang, "metamon_env_test_ffi", "set_env")
@external(javascript, "./metamon_env_test_ffi.mjs", "set_env")
fn set_env(name: String, value: String) -> Nil

@external(erlang, "metamon_env_test_ffi", "unset_env")
@external(javascript, "./metamon_env_test_ffi.mjs", "unset_env")
fn unset_env(name: String) -> Nil

@external(erlang, "metamon_env_test_ffi", "count_reset")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_reset")
fn count_reset() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_bump")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_bump")
fn count_bump() -> Nil

@external(erlang, "metamon_env_test_ffi", "count_get")
@external(javascript, "./metamon_env_test_ffi.mjs", "count_get")
fn count_get() -> Int
