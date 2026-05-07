import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import metamon/internal/regression.{Entry}

pub fn render_emits_all_required_fields_test() {
  let entry =
    Entry(
      mr_name: "snake_idempotent",
      config_seed: 42,
      run_index: 7,
      size: 50,
      edge_index: None,
      note: Some("OAuth2Token"),
      recorded: "2026-05-05T12:34:56Z",
    )
  let rendered = regression.render(entry)
  should.be_true(string.contains(rendered, "[[failures]]"))
  should.be_true(string.contains(rendered, "mr          = \"snake_idempotent\""))
  should.be_true(string.contains(rendered, "config_seed = 42"))
  should.be_true(string.contains(rendered, "run_index   = 7"))
  should.be_true(string.contains(rendered, "size        = 50"))
  should.be_true(string.contains(rendered, "edge_index = none"))
  should.be_true(string.contains(rendered, "note        = \"OAuth2Token\""))
  should.be_true(string.contains(
    rendered,
    "recorded    = \"2026-05-05T12:34:56Z\"",
  ))
}

pub fn render_handles_edge_index_test() {
  let entry =
    Entry(
      mr_name: "x",
      config_seed: 1,
      run_index: 0,
      size: 0,
      edge_index: Some(3),
      note: None,
      recorded: "now",
    )
  let rendered = regression.render(entry)
  should.be_true(string.contains(rendered, "edge_index = 3"))
}

pub fn round_trip_render_then_parse_test() {
  let entry =
    Entry(
      mr_name: "round_trip",
      config_seed: 99,
      run_index: 2,
      size: 30,
      edge_index: None,
      note: Some("hello"),
      recorded: "2026-05-05T01:00:00Z",
    )
  let rendered = regression.render(entry)
  let parsed = regression.parse(rendered)
  case parsed {
    [parsed_entry] -> should.equal(parsed_entry, entry)
    _ -> should.fail()
  }
}

pub fn parse_skips_malformed_blocks_test() {
  let raw = "[[failures]]\nmr = ::bad::\n[[failures]]\n"
  // Both blocks are malformed (the first has invalid value, the
  // second is empty); the parser should return [].
  let parsed = regression.parse(raw)
  should.equal(parsed, [])
}

pub fn parse_accepts_v0_legacy_files_without_version_header_test() {
  // Files written before schema_version was introduced have no
  // header line. The parser must still accept them.
  let entry =
    Entry(
      mr_name: "legacy",
      config_seed: 7,
      run_index: 0,
      size: 0,
      edge_index: None,
      note: None,
      recorded: "ts",
    )
  let raw = regression.render(entry)
  let parsed = regression.parse(raw)
  case parsed {
    [got] -> should.equal(got.mr_name, "legacy")
    _ -> should.fail()
  }
}

pub fn parse_accepts_v1_files_with_version_header_test() {
  let entry =
    Entry(
      mr_name: "v1",
      config_seed: 1,
      run_index: 0,
      size: 0,
      edge_index: None,
      note: None,
      recorded: "ts",
    )
  let raw = regression.version_header() <> "\n\n" <> regression.render(entry)
  let parsed = regression.parse(raw)
  case parsed {
    [got] -> should.equal(got.mr_name, "v1")
    _ -> should.fail()
  }
}

pub fn parse_with_version_rejects_unknown_schema_version_test() {
  // A future v99 file written by a newer metamon must be rejected
  // by the current parser, not silently mis-parsed.
  let raw = "schema_version = 99\n\n[[failures]]\nmr = \"future\"\n"
  case regression.parse_with_version(raw) {
    Ok(_) -> should.fail()
    Error(regression.UnsupportedSchemaVersion(found)) -> should.equal(found, 99)
    Error(_) -> should.fail()
  }
}

pub fn parse_with_version_rejects_malformed_version_test() {
  let raw = "schema_version = not_a_number\n\n[[failures]]\nmr = \"x\"\n"
  case regression.parse_with_version(raw) {
    Ok(_) -> should.fail()
    Error(regression.MalformedSchemaVersion(_)) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn parse_lenient_returns_empty_on_unknown_version_test() {
  // The lenient `parse` wrapper used by the runner returns [] (skip
  // replay) instead of bubbling the error so a stale checked-in
  // file does not abort the test run.
  let raw = "schema_version = 99\n\n[[failures]]\n"
  should.equal(regression.parse(raw), [])
}

pub fn version_header_exposes_current_value_test() {
  should.equal(
    regression.version_header(),
    "schema_version = "
      <> { regression.current_schema_version |> int_to_string },
  )
}

@external(erlang, "erlang", "integer_to_binary")
@external(javascript, "./metamon_ffi.mjs", "integer_to_string")
fn int_to_string(n: Int) -> String
