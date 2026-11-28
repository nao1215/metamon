//// Mutation testing for the project in the current directory: change one
//// operator, `!` or boolean literal in a module under `src/` at a time and
//// see whether `gleam test` notices. Run it on the Erlang target; the
//// [Mutation testing](mutation.html) page lists the commands and the files.
////
//// ```sh
//// gleam run -m metamon/mutation -- run --workers 8
//// gleam run -m metamon/mutation -- gate
//// gleam run -m metamon/mutation -- coverage
//// ```

import gleam/io
import metamon/internal/mutation

/// Runs the command given after `--`, printing the usage when there is none
/// or it is not known. Exits with 0 on success, 1 when `gate` or `doc-check`
/// fails or a test fails under `coverage`, and 2 on a usage or file error.
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
