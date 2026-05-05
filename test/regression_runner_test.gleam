//// End-to-end behaviour of regression file integration: when a
//// property is configured with `with_regression_file`, the runner
//// must (a) read existing entries on start-up and replay them, (b)
//// append the failing input to the file when a property fails.

import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range
import metamon/internal/regression
import simplifile

const tmp_path: String = "/tmp/metamon_regression_test.toml"

fn cleanup() -> Nil {
  let _ = simplifile.delete(tmp_path)
  Nil
}

pub fn write_records_failing_input_test() {
  cleanup()

  // Run a property that fails so the runner records a regression
  // entry, then read the file back and verify the entry shape.
  let outcome =
    capture_panic(fn() {
      let assert Ok(c) =
        metamon.with_regression_file(
          metamon.default_config()
            |> metamon.with_seed(metamon.seed(7)),
          tmp_path,
        )
      metamon.forall_with(
        c,
        generator.int(range.constant(0, 10)),
        // Always-failing property: triggers an immediate write.
        fn(_n) { False },
      )
    })

  should.equal(outcome.0, True)

  // The regression file must now exist and contain at least one
  // [[failures]] block for our property.
  let assert Ok(content) = simplifile.read(tmp_path)
  should.be_true(string.contains(content, "[[failures]]"))
  let entries = regression.parse(content)
  case entries {
    [] -> should.fail()
    [first, ..] -> {
      should.equal(first.mr_name, "(plain property)")
      // The recorded note should mention the input as inspected.
      case first.note {
        Some(_) -> Nil
        None -> should.fail()
      }
    }
  }

  cleanup()
}

pub fn read_replays_existing_entry_test() {
  cleanup()

  // Pre-seed a regression file with one entry. The runner must
  // replay it before any random generation, so when the property
  // fails the failure message must come from the replay path.
  let entry =
    regression.Entry(
      mr_name: "(plain property)",
      config_seed: 0,
      run_index: 0,
      size: 0,
      edge_index: Some(0),
      note: Some("from test"),
      recorded: "0",
    )
  let _ = simplifile.write(tmp_path, regression.render(entry))

  let observed =
    capture_panic(fn() {
      let assert Ok(c) =
        metamon.with_regression_file(
          metamon.default_config()
            |> metamon.with_seed(metamon.seed(7)),
          tmp_path,
        )
      metamon.forall_with(
        c,
        generator.return(0) |> generator.with_examples([42]),
        // Always-failing property; the replay path runs first, so
        // the failure must be tagged "regression replay".
        fn(_n) { False },
      )
    })

  should.equal(observed.0, True)
  should.be_true(string.contains(observed.1, "regression replay"))

  cleanup()
}

pub fn missing_file_is_silent_test() {
  cleanup()
  // Pointing at a non-existent file must not error; the runner
  // simply has nothing to replay and runs normally.
  let assert Ok(c) =
    metamon.with_regression_file(metamon.default_config(), tmp_path)
  metamon.forall_with(c, generator.int(range.constant(0, 9)), fn(n) {
    n >= 0 && n <= 9
  })
  cleanup()
}

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)
