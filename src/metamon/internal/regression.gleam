//// Regression file format: a small TOML-flavoured human-readable
//// log of past failures, recorded as `(seed, run_index, size,
//// edge_index)` reproduction keys (no values are serialised).
////
//// Files are append-only from the runner's perspective; the user
//// can manually delete or edit them.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// One regression entry. The runner re-runs each entry at the start
/// of the next session before falling back to fresh random inputs.
pub type Entry {
  Entry(
    mr_name: String,
    config_seed: Int,
    run_index: Int,
    size: Int,
    edge_index: Option(Int),
    note: Option(String),
    recorded: String,
  )
}

/// Render an entry as a TOML `[[failures]]` block.
pub fn render(entry: Entry) -> String {
  let edge_part = case entry.edge_index {
    None -> "edge_index = none"
    Some(i) -> "edge_index = " <> int.to_string(i)
  }
  let note_part = case entry.note {
    None -> ""
    Some(text) -> "\nnote        = " <> escape_string(text)
  }
  string.concat([
    "[[failures]]\n",
    "mr          = ",
    escape_string(entry.mr_name),
    "\n",
    "config_seed = ",
    int.to_string(entry.config_seed),
    "\n",
    "run_index   = ",
    int.to_string(entry.run_index),
    "\n",
    "size        = ",
    int.to_string(entry.size),
    "\n",
    edge_part,
    note_part,
    "\nrecorded    = ",
    escape_string(entry.recorded),
    "\n",
  ])
}

/// Parse the contents of a regression file into a list of entries.
/// The parser is intentionally lenient: malformed blocks are skipped
/// without failing, since the regression file is also human-edited.
pub fn parse(contents: String) -> List(Entry) {
  string.split(contents, "[[failures]]")
  |> list.filter_map(parse_block)
}

fn parse_block(raw: String) -> Result(Entry, Nil) {
  case string.trim(raw) {
    "" -> Error(Nil)
    trimmed -> parse_block_body(parse_lines(trimmed))
  }
}

fn parse_block_body(pairs: List(#(String, String))) -> Result(Entry, Nil) {
  case
    lookup(pairs, "mr"),
    lookup(pairs, "config_seed"),
    lookup(pairs, "run_index"),
    lookup(pairs, "size"),
    lookup(pairs, "edge_index"),
    lookup(pairs, "recorded")
  {
    Ok(mr), Ok(seed_str), Ok(run_str), Ok(size_str), Ok(edge_str), Ok(rec) ->
      build_entry(pairs, mr, seed_str, run_str, size_str, edge_str, rec)
    _, _, _, _, _, _ -> Error(Nil)
  }
}

fn build_entry(
  pairs: List(#(String, String)),
  mr: String,
  seed_str: String,
  run_str: String,
  size_str: String,
  edge_str: String,
  rec: String,
) -> Result(Entry, Nil) {
  case
    int.parse(seed_str),
    int.parse(run_str),
    int.parse(size_str),
    parse_edge(edge_str)
  {
    Ok(seed_value), Ok(run_value), Ok(size_value), Ok(edge) ->
      Ok(Entry(
        mr_name: strip_quotes(mr),
        config_seed: seed_value,
        run_index: run_value,
        size: size_value,
        edge_index: edge,
        note: lookup_note(pairs),
        recorded: strip_quotes(rec),
      ))
    _, _, _, _ -> Error(Nil)
  }
}

fn lookup_note(pairs: List(#(String, String))) -> Option(String) {
  case lookup(pairs, "note") {
    Ok(text) -> Some(strip_quotes(text))
    Error(_) -> None
  }
}

fn parse_lines(block: String) -> List(#(String, String)) {
  string.split(block, "\n")
  |> list.filter_map(parse_pair)
}

fn parse_pair(line: String) -> Result(#(String, String), Nil) {
  case string.split_once(line, "=") {
    Ok(#(left, right)) -> Ok(#(string.trim(left), string.trim(right)))
    Error(_) -> Error(Nil)
  }
}

fn lookup(pairs: List(#(String, String)), key: String) -> Result(String, Nil) {
  case pairs {
    [] -> Error(Nil)
    [#(k, v), ..rest] ->
      case k == key {
        True -> Ok(v)
        False -> lookup(rest, key)
      }
  }
}

fn parse_edge(value: String) -> Result(Option(Int), Nil) {
  case value {
    "none" -> Ok(None)
    raw ->
      case int.parse(raw) {
        Ok(n) -> Ok(Some(n))
        Error(_) -> Error(Nil)
      }
  }
}

fn strip_quotes(value: String) -> String {
  case string.starts_with(value, "\""), string.ends_with(value, "\"") {
    True, True ->
      value
      |> string.drop_start(1)
      |> string.drop_end(1)
    _, _ -> value
  }
}

fn escape_string(value: String) -> String {
  // Minimal: enclose in double quotes, escape internal double quotes.
  "\"" <> string.replace(value, "\"", "\\\"") <> "\""
}
