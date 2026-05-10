//// Robustness tests for the `regression.parse` / `parse_with_version`
//// path. (#84)
////
//// `with_regression_file` is metamon's only public surface that
//// ingests user-controlled file content from outside the test process.
//// A panic here cascades — every metamon invocation runs regression
//// replay first, so a malformed file silently breaks every test in
//// the suite, not just the regression-replay feature. Issue #58
//// pinned the format with a `schema_version` header and structured
//// `ParseError`. This module pins the **deviation** behaviour: how
//// the parser responds to the categories of malformed input that
//// real-world checked-in regression files actually encounter.
////
//// The contract being pinned (per the parser docstring):
////
//// - **Block-level malformed content**: silently skipped. The parser
////   is intentionally lenient because the file is human-edited.
//// - **Unknown future `schema_version`**: `parse_with_version` returns
////   `Error(UnsupportedSchemaVersion)`. The lenient `parse` wrapper
////   downgrades this to `[]` so a stale file from a newer metamon
////   does not abort the test run.
//// - **Malformed `schema_version` line** (non-integer value):
////   `Error(MalformedSchemaVersion)` from `parse_with_version`, `[]`
////   from `parse`.
//// - **Legacy v0 files** (no header): accepted as-is for backward
////   compatibility.
////
//// The tests use the parser directly (the parse path is the only
//// non-trivial logic; `simplifile.read` is just a String fetch).

import gleam/list
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range
import metamon/internal/regression

// ---------- helpers ----------

const valid_block: String = "[[failures]]\nmr          = \"x\"\nconfig_seed = 7\nrun_index   = 0\nsize        = 0\nedge_index = none\nrecorded    = \"2026-01-01T00:00:00Z\"\n"

fn header_v1() -> String {
  "schema_version = 1\n"
}

// ---------- 1. Malformed TOML ----------

pub fn parse_malformed_toml_returns_empty_test() {
  // A developer hand-editing a regression file during a merge
  // conflict could leave behind something like "this is not [valid
  // toml ===". The parser must stay lenient on garbage and return
  // an empty list rather than panic.
  let parsed = regression.parse("this is not [valid toml ===")
  should.equal(parsed, [])
}

pub fn parse_with_version_malformed_toml_returns_ok_empty_test() {
  // Without a schema_version line, the parser treats malformed
  // content as a legacy v0 file and just produces no entries.
  case regression.parse_with_version("this is not [valid toml ===") {
    Ok(entries) -> should.equal(entries, [])
    Error(_) -> should.fail()
  }
}

// ---------- 2. Truncated file ----------

pub fn parse_truncated_block_skips_partial_test() {
  // A regression file truncated mid-block (e.g. an interrupted
  // previous run, a CI cache miss, a partial download) leaves a
  // [[failures]] header without a complete body. The parser must
  // skip the partial block, not panic.
  let truncated =
    header_v1() <> valid_block <> "[[failures]]\nmr          = \"truncated"
  let parsed = regression.parse(truncated)
  // The first complete block is preserved; the second (truncated)
  // is silently skipped.
  case parsed {
    [entry] -> should.equal(entry.mr_name, "x")
    _ -> should.fail()
  }
}

// ---------- 3. Unknown future schema_version ----------

pub fn parse_with_version_rejects_future_schema_version_test() {
  // A v2+ file is a forward-compatibility scenario: the file was
  // written by a newer metamon, the user downgraded. `parse_with_version`
  // must return an explicit error (not silently mis-parse forward-
  // incompatible content).
  case regression.parse_with_version("schema_version = 999\n" <> valid_block) {
    Error(regression.UnsupportedSchemaVersion(999)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_lenient_skips_replay_on_future_schema_version_test() {
  // The lenient `parse` wrapper used by the runner downgrades the
  // schema-version error to an empty list so a stale checked-in
  // file does not abort the test run — replay just gets skipped.
  let parsed = regression.parse("schema_version = 999\n" <> valid_block)
  should.equal(parsed, [])
}

// ---------- 4. Malformed schema_version line ----------

pub fn parse_with_version_rejects_non_integer_schema_version_test() {
  // A user typo in the schema_version line (e.g. quoting it as a
  // string) must surface as a structured MalformedSchemaVersion.
  case
    regression.parse_with_version(
      "schema_version = \"not-a-number\"\n" <> valid_block,
    )
  {
    Error(regression.MalformedSchemaVersion(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_lenient_skips_on_malformed_schema_version_test() {
  let parsed =
    regression.parse("schema_version = \"not-a-number\"\n" <> valid_block)
  should.equal(parsed, [])
}

// ---------- 5. Bad value types in known keys ----------

pub fn parse_skips_block_with_non_integer_seed_test() {
  // `config_seed = "not-a-number"` is one of the issue's named
  // failure modes. The block-level parser is lenient by design
  // (skip the bad block, keep the good ones), so a mixed file
  // returns only the parseable entries.
  let mixed =
    header_v1()
    <> valid_block
    <> "[[failures]]\nmr          = \"bad\"\nconfig_seed = \"not-a-number\"\nrun_index   = 0\nsize        = 0\nedge_index = none\nrecorded    = \"now\"\n"
  let parsed = regression.parse(mixed)
  case parsed {
    [entry] -> should.equal(entry.mr_name, "x")
    _ -> should.fail()
  }
}

pub fn parse_skips_block_missing_required_field_test() {
  // A block that omits a required field (here: `recorded`) is also
  // skipped silently. The contract is "extract what you can, ignore
  // the rest" — the alternative would force the user to manually
  // recover after every merge conflict.
  let missing_field =
    header_v1()
    <> "[[failures]]\nmr          = \"missing\"\nconfig_seed = 0\nrun_index   = 0\nsize        = 0\nedge_index = none\n"
  let parsed = regression.parse(missing_field)
  should.equal(parsed, [])
}

// ---------- 6. Encoding surprises (BOM, CRLF) ----------

pub fn parse_handles_crlf_line_endings_test() {
  // A regression file checked out on Windows (or via a misconfigured
  // .gitattributes) lands on disk with CRLF. The parser splits on
  // "\n" so CRLF leaves a trailing "\r" on every value, but every
  // value goes through `string.trim` which strips the "\r" — so
  // CRLF round-trips correctly. Pin this so a future refactor that
  // drops the trim would visibly flip this test.
  let crlf = string.replace(header_v1() <> valid_block, "\n", "\r\n")
  let parsed = regression.parse(crlf)
  case parsed {
    [entry] -> should.equal(entry.mr_name, "x")
    _ -> should.fail()
  }
}

pub fn parse_handles_utf8_bom_prefix_test() {
  // A file edited and re-saved by certain Windows editors gains a
  // UTF-8 BOM (U+FEFF). The BOM prefix means the first line is no
  // longer "schema_version = 1" but "<BOM>schema_version = 1", so
  // the version line check sees a key that doesn't equal
  // "schema_version" and treats the file as legacy v0.
  let bom = "\u{FEFF}" <> header_v1() <> valid_block
  let parsed = regression.parse(bom)
  // The valid_block is still parseable since block parsing splits
  // on "[[failures]]" which is unaffected by the BOM.
  case parsed {
    [entry] -> should.equal(entry.mr_name, "x")
    _ -> should.fail()
  }
}

// ---------- 7. Large / adversarial input ----------

pub fn parse_handles_many_blocks_test() {
  // A regression file accumulated over months on a busy CI could
  // grow to thousands of blocks. The parser walks the file
  // linearly; the contract is "linear time, no stack blow-up,
  // returns every parseable entry".
  let many_blocks = header_v1() <> string.repeat(valid_block, 200)
  let parsed = regression.parse(many_blocks)
  should.equal(list.length(parsed), 200)
}

pub fn parse_handles_many_repeated_keys_in_one_block_test() {
  // TOML technically rejects duplicate keys in one table, but the
  // metamon parser is line-based and treats the *first* matching
  // key as the value (`lookup` returns on first hit). Pin this so
  // a future TOML-strict refactor can choose between matching
  // current behaviour and rejecting the block.
  let dupes =
    header_v1()
    <> "[[failures]]\nmr          = \"first\"\nmr          = \"second\"\nconfig_seed = 1\nrun_index   = 0\nsize        = 0\nedge_index = none\nrecorded    = \"now\"\n"
  let parsed = regression.parse(dupes)
  case parsed {
    [entry] -> should.equal(entry.mr_name, "first")
    _ -> should.fail()
  }
}

// ---------- 8. Property-based fuzz: parser never panics ----------

pub fn regression_parse_no_panic_under_printable_ascii_fuzz_test() {
  // metamon dogfooding: fuzz the regression-file parser with its
  // own printable-ASCII string generator. The property is "no
  // panic" — `parse` returns `List(Entry)`, never raises. A few
  // hundred iterations is enough to surface any input-shape that
  // panics through the lenient parse path.
  metamon.forall_with(
    metamon.default_config()
      |> metamon.with_runs_or_panic(200),
    generator.string_printable_ascii(range.constant(0, 256)),
    fn(payload) {
      // Discard the result — only "did this return?" matters.
      let _ = regression.parse(payload)
      True
    },
  )
}

pub fn regression_parse_no_panic_under_unicode_fuzz_test() {
  // Same dogfooding loop with a Unicode generator. Catches the
  // BOM / non-ASCII byte-class cases that printable-ASCII alone
  // would miss.
  metamon.forall_with(
    metamon.default_config()
      |> metamon.with_runs_or_panic(200),
    generator.string_unicode(range.constant(0, 64)),
    fn(payload) {
      let _ = regression.parse(payload)
      True
    },
  )
}

pub fn regression_parse_with_version_no_panic_under_fuzz_test() {
  // Same property for the strict variant. It returns
  // `Result(List(Entry), ParseError)`; either outcome is fine.
  metamon.forall_with(
    metamon.default_config()
      |> metamon.with_runs_or_panic(200),
    generator.string_printable_ascii(range.constant(0, 256)),
    fn(payload) {
      let _ = regression.parse_with_version(payload)
      True
    },
  )
}

// ---------- 9. Empty file ----------

pub fn parse_handles_empty_string_test() {
  let parsed = regression.parse("")
  should.equal(parsed, [])
}

pub fn parse_with_version_handles_empty_string_test() {
  case regression.parse_with_version("") {
    Ok(entries) -> should.equal(entries, [])
    Error(_) -> should.fail()
  }
}

// ---------- 10. Spot-check that valid inputs still parse ----------

pub fn parse_baseline_valid_input_still_works_test() {
  // Belt-and-braces: a baseline pass on a known-good input ensures
  // the helper constants used above are themselves correct, so a
  // failure of the lenient tests above isn't shadowed by a typo
  // in `valid_block`.
  let parsed = regression.parse(header_v1() <> valid_block)
  case parsed {
    [entry] -> {
      should.equal(entry.mr_name, "x")
      should.equal(entry.config_seed, 7)
    }
    _ -> should.fail()
  }
}
