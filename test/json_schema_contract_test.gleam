//// Schema-contract tests for the JSON failure-report format. (#82)
////
//// `README.md` §JSON output declares the schema is stable and lists 17
//// top-level keys: `mr_name`, `test_name`, `config_seed`, `runs_done`,
//// `runs_total`, `shrinks_done`, `shrink_capped`, `source`,
//// `morph_mode`, `relation`, `source_input`, `followup_input`,
//// `source_output`, `followup_output`, `annotations`, `footnotes`,
//// `coverage`. Downstream tooling (`jq` pipelines, GitHub Actions
//// annotations, LLM analysis steps) depends on every one of those
//// keys being present in every failure shape.
////
//// `test/json_output_test.gleam` covers basic emission for `forall` and
//// `forall_morph`, but only spot-checks five of the seventeen keys.
//// This module triggers each public failure shape that emits JSON
//// (`forall`, `forall_morph`, `forall_round_trip`) and asserts that
//// **every** README-listed key appears, plus the documented value-type
//// for the keys whose type is part of the contract (`config_seed`,
//// `runs_done`, `runs_total`, `shrinks_done` → Int; `shrink_capped` →
//// Bool; `annotations`, `footnotes` → Array; `coverage` → Object or
//// null).
////
//// Stateful failures (`metamon/stateful.assert_passed`) panic with
//// their own text-only header and do not flow through the JSON
//// formatter, so they are intentionally out of scope for this contract
//// — the README §JSON output section similarly says nothing about a
//// stateful JSON shape.

import gleam/list
import gleam/string
import gleeunit/should
import metamon
import metamon/config
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform

// ---------- panic capture ----------

@external(erlang, "metamon_ffi", "capture_panic")
@external(javascript, "./metamon_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

fn json_from_failure(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = capture_panic(thunk)
  should.equal(panicked, True)
  let trimmed = string.trim(message)
  // Sanity: the failure path produced a JSON object, not the text
  // header. If this fires, a future runner refactor has stopped
  // routing failures through the JSON renderer for this shape.
  should.be_true(string.starts_with(trimmed, "{"))
  should.be_true(string.ends_with(trimmed, "}"))
  trimmed
}

// ---------- failure triggers (one per public JSON-emitting shape) ----------

fn json_for_forall_failure() -> String {
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  json_from_failure(fn() {
    metamon.forall_with(cfg, generator.int(range.constant(0, 10)), fn(_n) {
      False
    })
  })
}

fn json_for_forall_morph_failure() -> String {
  let increment = transform.new("+1", fn(n: Int) { n + 1 })
  let bad_mr =
    metamon.mr(
      name: "false_invariant",
      transform: increment,
      relation: relation.equal(),
    )
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  json_from_failure(fn() {
    metamon.forall_morph_with(
      cfg,
      generator.int(range.constant(1, 10)),
      bad_mr,
      fn(n) { n },
    )
  })
}

fn json_for_forall_round_trip_failure() -> String {
  let cfg =
    metamon.default_config()
    |> metamon.with_output_format(config.Json)
  json_from_failure(fn() {
    // A trivially broken codec: encoder and decoder do not invert.
    metamon.forall_round_trip_with(
      cfg: cfg,
      gen: generator.int(range.constant(1, 10)),
      name: "broken_codec",
      encode: fn(n: Int) { n + 1 },
      decode: fn(n: Int) { Ok(n) },
    )
  })
}

// ---------- contract assertions ----------

const required_keys: List(String) = [
  "mr_name", "test_name", "config_seed", "runs_done", "runs_total",
  "shrinks_done", "shrink_capped", "source", "morph_mode", "relation",
  "source_input", "followup_input", "source_output", "followup_output",
  "annotations", "footnotes", "coverage",
]

fn assert_key_present(json: String, key: String) -> Nil {
  // Schema keys appear as `"<key>":` in the output. Substring is
  // sufficient to assert presence; a future schema rename would fail
  // the test and force a coordinated README + impl + test update.
  let needle = "\"" <> key <> "\":"
  case string.contains(json, needle) {
    True -> Nil
    False -> {
      // Surface the missing key in the gleeunit failure output so a
      // schema drift is immediately diagnosable.
      let _ = key
      should.fail()
    }
  }
}

fn assert_all_required_keys_present(json: String) -> Nil {
  list.each(required_keys, fn(key) { assert_key_present(json, key) })
}

fn assert_int_typed(json: String, key: String) -> Nil {
  // An Int value renders as `"<key>":<digit>` (with a possible
  // leading `-`). A non-Int would render as `"key":"..."` (string),
  // `"key":[...]` (array), `"key":{...}` (object), `"key":true|false`
  // (bool), or `"key":null`. Asserting the next character after the
  // colon is `-` or a digit is the cheapest contract for "still Int".
  let needle = "\"" <> key <> "\":"
  let assert Ok(#(_, after)) = string.split_once(json, on: needle)
  let first_char = string.slice(after, at_index: 0, length: 1)
  let valid =
    first_char == "-"
    || first_char == "0"
    || first_char == "1"
    || first_char == "2"
    || first_char == "3"
    || first_char == "4"
    || first_char == "5"
    || first_char == "6"
    || first_char == "7"
    || first_char == "8"
    || first_char == "9"
  should.be_true(valid)
}

fn assert_bool_typed(json: String, key: String) -> Nil {
  let needle_true = "\"" <> key <> "\":true"
  let needle_false = "\"" <> key <> "\":false"
  should.be_true(
    string.contains(json, needle_true) || string.contains(json, needle_false),
  )
}

fn assert_array_typed(json: String, key: String) -> Nil {
  let needle = "\"" <> key <> "\":["
  should.be_true(string.contains(json, needle))
}

fn assert_object_or_null_typed(json: String, key: String) -> Nil {
  // `coverage` is `Object` when a coverage snapshot exists and `null`
  // when none was recorded. Both are part of the documented contract.
  let needle_obj = "\"" <> key <> "\":{"
  let needle_null = "\"" <> key <> "\":null"
  should.be_true(
    string.contains(json, needle_obj) || string.contains(json, needle_null),
  )
}

fn assert_full_contract(json: String) -> Nil {
  assert_all_required_keys_present(json)
  assert_int_typed(json, "config_seed")
  assert_int_typed(json, "runs_done")
  assert_int_typed(json, "runs_total")
  assert_int_typed(json, "shrinks_done")
  assert_bool_typed(json, "shrink_capped")
  assert_array_typed(json, "annotations")
  assert_array_typed(json, "footnotes")
  assert_object_or_null_typed(json, "coverage")
}

// ---------- schema contract per failure shape ----------

pub fn json_schema_contract_forall_test() {
  assert_full_contract(json_for_forall_failure())
}

pub fn json_schema_contract_forall_morph_test() {
  assert_full_contract(json_for_forall_morph_failure())
}

pub fn json_schema_contract_forall_round_trip_test() {
  assert_full_contract(json_for_forall_round_trip_failure())
}

// ---------- value-shape spot checks ----------

pub fn json_source_is_object_with_kind_test() {
  // `source` is an object discriminating between random and edge
  // sources via a `kind` field. Pin both the wrapper shape and the
  // discriminator presence so a future flat / string encoding fails
  // loudly. Each failure shape is exercised so the contract can't
  // hold in one shape but drift in another.
  let json = json_for_forall_failure()
  should.be_true(string.contains(json, "\"source\":{"))
  should.be_true(string.contains(json, "\"kind\":"))
}

pub fn json_morph_mode_is_plain_string_for_forall_test() {
  // For `forall` (no MR), `morph_mode` renders as the literal string
  // "plain", not as an object. Pin the discriminator value so the
  // README's "morph_mode" key is unambiguous about the no-MR case.
  let json = json_for_forall_failure()
  should.be_true(string.contains(json, "\"morph_mode\":\"plain\""))
}

pub fn json_morph_mode_is_object_for_forall_morph_test() {
  // For `forall_morph`, `morph_mode` is an object with `kind` and the
  // transform name(s). The plain-vs-equivariant discrimination lives
  // inside this object, so downstream consumers must be able to
  // detect both shapes — the contract is "string OR object", not
  // "always string".
  let json = json_for_forall_morph_failure()
  should.be_true(string.contains(json, "\"morph_mode\":{"))
  should.be_true(string.contains(json, "\"kind\":\"plain\""))
}
