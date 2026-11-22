# Targets

metamon runs on Erlang and JavaScript. Generators use a 32-bit xorshift generator written in Gleam, so the same seed produces the same inputs on both targets. `classify`, `cover` and `annotate` keep per-run state in the process dictionary on Erlang and in a module-level `Map` on JavaScript.

## Requirements

- Gleam 1.14 or later.
- Erlang/OTP 27 or later. CI tests OTP 27, 28 and 29.
- Node.js 22 or later. CI tests Node 22 and the current LTS.

## Differences between targets

See [Limitations](limitations.html) for running properties concurrently on JavaScript and for float special values on Erlang.
