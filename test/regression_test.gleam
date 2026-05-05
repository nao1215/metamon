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
