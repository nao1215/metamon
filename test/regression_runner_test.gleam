//// End-to-end behaviour of regression file integration: when a
//// property is configured with `with_regression_file`, the runner
//// must (a) read existing entries on start-up and replay them, (b)
//// append the failing input to the file when a property fails.

import gleam/list
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

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

const shared_path: String = "/tmp/metamon_regression_shared_test.toml"

fn round_trip_with_file(
  name: String,
  seed: Int,
  broken: fn(Int) -> Bool,
) -> Nil {
  metamon.forall_round_trip_with(
    cfg: metamon.default_config()
      |> metamon.with_seed(metamon.seed(seed))
      |> metamon.with_regression_file_or_panic(shared_path),
    gen: generator.int(range.constant(0, 1000)) |> generator.no_edges,
    name: name,
    encode: fn(n) { n },
    decode: fn(n) {
      case broken(n) {
        True -> Ok(n + 1)
        False -> Ok(n)
      }
    },
  )
}

pub fn round_trips_sharing_a_file_replay_only_their_own_entries_test() {
  let _ = simplifile.delete(shared_path)
  // `b` breaks only on 163, which its own seed never generates.
  let b = fn() { round_trip_with_file("b", 7, fn(n) { n == 163 }) }
  b()
  // `a` fails first on 163 and records it.
  let a = fn() { round_trip_with_file("a", 42, fn(n) { n >= 10 }) }
  let #(panicked, _) = capture_panic(a)
  should.be_true(panicked)
  let assert Ok(content) = simplifile.read(shared_path)
  should.be_true(string.contains(content, "mr          = \"round_trip[a]\""))
  should.be_true(string.contains(content, "note        = \"163\""))
  // The entry recorded for `a` is not replayed against `b`.
  b()
  // `a` still replays its own entry.
  let #(panicked, text) = capture_panic(a)
  should.be_true(panicked)
  should.be_true(string.contains(text, "regression replay for `round_trip[a]`"))
  let _ = simplifile.delete(shared_path)
  Nil
}

pub fn unwritable_regression_file_is_reported_test() {
  let path = "/tmp/metamon-no-such-directory/regressions.toml"
  let #(panicked, text) =
    capture_panic(fn() {
      metamon.forall_with(
        metamon.default_config()
          |> metamon.with_regression_file_or_panic(path),
        generator.int(range.constant(0, 10)),
        fn(_) { False },
      )
    })
  should.be_true(panicked)
  should.be_true(string.contains(
    text,
    "  footnotes:\n    - could not write the regression file " <> path,
  ))
}

pub fn regression_entries_share_one_header_test() {
  let _ = simplifile.delete(shared_path)
  let fail = fn(name) {
    capture_panic(fn() { round_trip_with_file(name, 42, fn(_) { True }) })
  }
  let _ = fail("one")
  let _ = fail("two")
  let assert Ok(content) = simplifile.read(shared_path)
  should.be_true(string.starts_with(
    content,
    "schema_version = 1\n\n[[failures]]\n",
  ))
  should.equal(list.length(string.split(content, "schema_version")), 2)
  should.equal(list.length(regression.parse(content)), 2)
  let _ = simplifile.delete(shared_path)
  Nil
}

pub fn future_schema_version_file_is_not_replayed_test() {
  let entry =
    regression.Entry(
      mr_name: "(plain property)",
      config_seed: 0,
      run_index: 0,
      size: 0,
      edge_index: Some(0),
      note: None,
      recorded: "0",
    )
  let run = fn(version: String) {
    cleanup()
    let _ =
      simplifile.write(
        tmp_path,
        "schema_version = " <> version <> "\n\n" <> regression.render(entry),
      )
    let #(panicked, text) =
      capture_panic(fn() {
        metamon.forall_with(
          metamon.default_config()
            |> metamon.with_regression_file_or_panic(tmp_path),
          generator.int(range.constant(0, 9)),
          fn(_) { False },
        )
      })
    cleanup()
    should.be_true(panicked)
    string.contains(text, "regression replay")
  }
  // The current schema replays the entry; a newer one is skipped and
  // the property fails on its own runs instead.
  should.be_true(run("1"))
  should.be_false(run("99"))
}
