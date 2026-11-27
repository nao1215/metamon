//// Mutation testing for Gleam projects. It parses each module under `src/`
//// with glance, changes one operator, `!` or boolean literal at a time, and
//// runs `gleam test --target erlang` in a copy of the project. A mutant the
//// tests still pass with has survived: some behaviour is not checked.
////
//// Add metamon as a dev dependency and run it from the project root on the
//// Erlang target. It needs `timeout` from GNU coreutils (`gtimeout` on
//// macOS).
////
//// ```sh
//// gleam run -m metamon/mutation -- run --workers 4
//// gleam run -m metamon/mutation -- baseline
//// gleam run -m metamon/mutation -- run src/my_module.gleam
//// gleam run -m metamon/mutation -- gate
//// ```
////
//// `run` writes `build/mutation/results.json`. `baseline` copies a run over
//// every module to `doc/mutation/baseline.json`, and rewrites the table
//// between `<!-- mutation:start -->` and `<!-- mutation:end -->` in
//// `doc/testing.md` when the file has them. `gate` fails when a mutant lives
//// that the baseline does not list, so a pull request can mutate only the
//// modules it changes. Survivors are matched by module, function, mutator,
//// line text and the column in that text, so moved code still matches. A
//// survivor is run two more times and counts only when it lives every time,
//// because property tests draw a new seed on each run. `--exclude FILE`
//// leaves a module out, such as generated tables.

import gleam/io
import metamon/internal/mutation

pub fn main() -> Nil {
  let code = case mutation.parse_arguments(plain_arguments()) {
    Error(Nil) -> {
      io.println(mutation.usage)
      2
    }
    Ok(command) ->
      case mutation.execute(command) {
        Ok(code) -> code
        Error(error) -> {
          io.println_error(mutation.describe(error))
          2
        }
      }
  }
  case code {
    0 -> Nil
    _ -> halt(code)
  }
}

@external(erlang, "metamon_ffi", "plain_arguments")
@external(javascript, "../metamon_ffi.mjs", "plain_arguments")
fn plain_arguments() -> List(String)

@external(erlang, "erlang", "halt")
@external(javascript, "node:process", "exit")
fn halt(code: Int) -> Nil
