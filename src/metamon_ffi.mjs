// JavaScript-target FFI for metamon. Mirrors the Erlang implementation
// closely so generators and runners produce identical results across
// targets. State is held on a per-module Map keyed by string; tests on
// the JS target run sequentially within a single global, but gleeunit
// already isolates assertion lifetimes per test, so reuse is safe as
// long as the runner clears state at the start and end of each run.

import { Ok, Error as ErrorResult } from "./gleam.mjs";

export function now_microseconds() {
  // Date.now() returns milliseconds; multiply to match the Erlang
  // microsecond clock used by Seed.random_seed/0.
  return Date.now() * 1000;
}

export function codepoint_to_string(codepoint) {
  return String.fromCodePoint(codepoint);
}

export function integer_to_string(n) {
  return String(n);
}

export function float_to_string(n) {
  return String(n);
}

export function string_length_js(s) {
  // Codepoint length, not UTF-16 code-unit length, to match the Erlang
  // `string:length/1` behaviour used in the generator tests.
  let count = 0;
  for (const _ of s) count += 1;
  return count;
}

export function capture_panic(thunk) {
  // Mirror of `metamon_ffi:capture_panic/1` — runs `thunk` and reports
  // `(panicked, message)` to the caller. Used by tests that exercise
  // the failure path of `metamon.forall` without aborting the test
  // process.
  try {
    thunk();
    return [false, ""];
  } catch (error) {
    let message;
    if (error && typeof error === "object" && error.message) {
      message = error.message;
    } else {
      message = String(error);
    }
    return [true, message];
  }
}

const stateStore = new Map();

export function state_put(key, value) {
  stateStore.set(key, value);
  return undefined;
}

export function state_get(key) {
  if (stateStore.has(key)) {
    return new Ok(stateStore.get(key));
  }
  return new ErrorResult(undefined);
}

export function state_erase(key) {
  stateStore.delete(key);
  return undefined;
}

export function identity(x) {
  return x;
}

export function state_keys() {
  return Array.from(stateStore.keys()).reduce(
    (acc, key) => ({ head: key, tail: acc }),
    { head: undefined, tail: undefined, isEmpty: true },
  );
}
