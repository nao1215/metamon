//// Structural diff for failure reports. Compares two values
//// element-by-element and produces a tree that the formatter can
//// render compactly.
////
//// The implementation is type-erased: it inspects the dynamic shape
//// of each side via `string.inspect`. This is sufficient for the
//// failure-report use case (we only need to *display* the diff, not
//// reason about it programmatically), and avoids requiring users to
//// supply per-type formatters.

import gleam/int
import gleam/list
import gleam/string

/// One node in a diff tree.
pub type Diff {
  /// Both sides identical at this position.
  Same(rendered: String)

  /// Sides differ — show both rendered values.
  Differ(left: String, right: String)

  /// Element-wise diff for lists.
  ListDiff(items: List(IndexedDiff))

  /// Element-wise diff for tuples.
  TupleDiff(items: List(IndexedDiff))

  /// Multi-line diff for strings (line-by-line LCS).
  StringDiff(left: String, right: String, segments: List(Segment))
}

/// A list element together with its position.
pub type IndexedDiff {
  IndexedDiff(index: Int, diff: Diff)
}

/// One section of a multi-line string diff.
pub type Segment {
  Common(text: String)
  Removed(text: String)
  Added(text: String)
}

/// Compute a structural diff between two values. Equal inputs collapse
/// to `Same`; otherwise the result depends on whether
/// `string.inspect` exposes list-shaped or string-shaped output.
pub fn diff(left: a, right: a) -> Diff {
  case left == right {
    True -> Same(rendered: string.inspect(left))
    False -> diff_inspected(string.inspect(left), string.inspect(right))
  }
}

/// `diff` for two values already rendered with `string.inspect`. The
/// failure report keeps only the rendered outputs, so it diffs them with
/// this rather than inspecting the strings a second time.
@internal
pub fn diff_inspected(left: String, right: String) -> Diff {
  case left == right {
    True -> Same(rendered: left)
    False -> shape_aware_diff(left, right)
  }
}

fn shape_aware_diff(l_str: String, r_str: String) -> Diff {
  case
    is_list_inspect(l_str),
    is_list_inspect(r_str),
    is_tuple_inspect(l_str),
    is_tuple_inspect(r_str)
  {
    True, True, _, _ -> list_diff_from_inspect(l_str, r_str)
    _, _, True, True -> tuple_diff_from_inspect(l_str, r_str)
    _, _, _, _ -> Differ(left: l_str, right: r_str)
  }
}

fn is_list_inspect(s: String) -> Bool {
  string.starts_with(s, "[") && string.ends_with(s, "]")
}

fn is_tuple_inspect(s: String) -> Bool {
  string.starts_with(s, "#(") && string.ends_with(s, ")")
}

fn list_diff_from_inspect(left: String, right: String) -> Diff {
  let l_items = split_top_level(left)
  let r_items = split_top_level(right)
  ListDiff(items: zip_items(l_items, r_items, 0))
}

fn tuple_diff_from_inspect(left: String, right: String) -> Diff {
  // `#(...)` → drop the leading `#` then reuse the bracket-stripping
  // path. `split_top_level` accepts an arbitrary `(...)` body too.
  let l_inner = drop_tuple_prefix(left)
  let r_inner = drop_tuple_prefix(right)
  let l_items = split_top_level(l_inner)
  let r_items = split_top_level(r_inner)
  TupleDiff(items: zip_items(l_items, r_items, 0))
}

fn drop_tuple_prefix(inspected: String) -> String {
  case string.starts_with(inspected, "#(") {
    True -> "(" <> string.drop_start(inspected, 2)
    False -> inspected
  }
}

fn zip_items(
  left: List(String),
  right: List(String),
  index: Int,
) -> List(IndexedDiff) {
  case left, right {
    [], [] -> []
    [], [r, ..rs] -> [
      IndexedDiff(index: index, diff: Differ(left: "·", right: r)),
      ..zip_items([], rs, index + 1)
    ]
    [l, ..ls], [] -> [
      IndexedDiff(index: index, diff: Differ(left: l, right: "·")),
      ..zip_items(ls, [], index + 1)
    ]
    [l, ..ls], [r, ..rs] -> {
      let inner = case l == r {
        True -> Same(rendered: l)
        False -> Differ(left: l, right: r)
      }
      [IndexedDiff(index: index, diff: inner), ..zip_items(ls, rs, index + 1)]
    }
  }
}

fn split_top_level(inspected: String) -> List(String) {
  // Strip the enclosing brackets and walk character-by-character,
  // tracking nesting depth so commas inside sub-structures don't
  // cause splits. Accepts both `[...]` (lists) and `(...)` (tuples
  // after `drop_tuple_prefix`).
  let inner = case
    string.starts_with(inspected, "["),
    string.ends_with(inspected, "]")
  {
    True, True ->
      inspected
      |> string.drop_start(1)
      |> string.drop_end(1)
    _, _ ->
      case
        string.starts_with(inspected, "("),
        string.ends_with(inspected, ")")
      {
        True, True ->
          inspected
          |> string.drop_start(1)
          |> string.drop_end(1)
        _, _ -> inspected
      }
  }
  walk_and_split(string.to_graphemes(inner), Outside, 0, [], [])
}

/// Where `walk_and_split` is relative to string literals: commas and
/// brackets inside `"..."` do not split, and `\` escapes the next
/// character. Outside strings, `[`, `(` and each `<` of `<<` open a level.
type Scan {
  Outside
  InString
  Escaped
}

/// `acc` holds the current item's graphemes in reverse.
fn walk_and_split(
  graphemes: List(String),
  scan: Scan,
  depth: Int,
  acc: List(String),
  results: List(String),
) -> List(String) {
  case graphemes {
    [] -> finish_split(acc, results)
    [first, ..rest] ->
      case scan, first, depth {
        Escaped, _, _ ->
          walk_and_split(rest, InString, depth, [first, ..acc], results)
        InString, "\\", _ ->
          walk_and_split(rest, Escaped, depth, [first, ..acc], results)
        InString, "\"", _ ->
          walk_and_split(rest, Outside, depth, [first, ..acc], results)
        InString, _, _ ->
          walk_and_split(rest, InString, depth, [first, ..acc], results)
        Outside, "\"", _ ->
          walk_and_split(rest, InString, depth, [first, ..acc], results)
        Outside, "[", _ | Outside, "(", _ | Outside, "<", _ ->
          walk_and_split(rest, Outside, depth + 1, [first, ..acc], results)
        Outside, "]", d | Outside, ")", d | Outside, ">", d if d > 0 ->
          walk_and_split(rest, Outside, d - 1, [first, ..acc], results)
        Outside, ",", 0 ->
          walk_and_split(rest, Outside, 0, [], [item_text(acc), ..results])
        Outside, _, _ ->
          walk_and_split(rest, Outside, depth, [first, ..acc], results)
      }
  }
}

fn item_text(reversed: List(String)) -> String {
  reversed |> list.reverse |> string.concat |> string.trim
}

fn finish_split(acc: List(String), results: List(String)) -> List(String) {
  case item_text(acc) {
    "" -> list.reverse(results)
    trimmed -> list.reverse([trimmed, ..results])
  }
}

/// Multi-line string diff using a longest-common-subsequence (LCS) on
/// lines. Lines unique to the left side are shown as `Removed`, lines
/// unique to the right are shown as `Added`, lines present in both
/// are shown as `Common`.
pub fn diff_string(left: String, right: String) -> Diff {
  case left == right {
    True -> Same(rendered: left)
    False -> {
      let l_lines = string.split(left, "\n")
      let r_lines = string.split(right, "\n")
      let segments = line_diff(l_lines, r_lines)
      StringDiff(left: left, right: right, segments: segments)
    }
  }
}

/// Render a `Diff` as a human-readable multi-line string.
pub fn render(d: Diff) -> String {
  render_with_indent(d, "")
}

fn render_with_indent(d: Diff, indent: String) -> String {
  case d {
    Same(rendered) -> indent <> "= " <> rendered
    Differ(left, right) ->
      indent <> "- " <> left <> "\n" <> indent <> "+ " <> right
    ListDiff(items) -> render_list_diff(items, indent, "[#")
    TupleDiff(items) -> render_list_diff(items, indent, "#.")
    StringDiff(_, _, segments) -> render_string_diff(segments, indent)
  }
}

fn render_list_diff(
  items: List(IndexedDiff),
  indent: String,
  prefix: String,
) -> String {
  let close = case prefix {
    "#." -> ""
    _ -> "]"
  }
  list.map(items, fn(item: IndexedDiff) {
    indent
    <> prefix
    <> int.to_string(item.index)
    <> close
    <> "\n"
    <> render_with_indent(item.diff, indent <> "  ")
  })
  |> string.join("\n")
}

fn render_string_diff(segments: List(Segment), indent: String) -> String {
  list.map(segments, fn(segment) {
    case segment {
      Common(text) -> indent <> "  " <> text
      Removed(text) -> indent <> "- " <> text
      Added(text) -> indent <> "+ " <> text
    }
  })
  |> string.join("\n")
}

// Walk both sides in lockstep: equal lines are `Common`, and where they
// diverge the left line is `Removed` and the right line `Added`. This is
// enough for short, mostly aligned outputs.
fn line_diff(left: List(String), right: List(String)) -> List(Segment) {
  line_diff_loop(left, right, [])
}

fn line_diff_loop(
  left: List(String),
  right: List(String),
  acc: List(Segment),
) -> List(Segment) {
  case left, right {
    [], [] -> list.reverse(acc)
    [], [r, ..rs] -> line_diff_loop([], rs, [Added(r), ..acc])
    [l, ..ls], [] -> line_diff_loop(ls, [], [Removed(l), ..acc])
    [l, ..ls], [r, ..rs] if l == r -> line_diff_loop(ls, rs, [Common(l), ..acc])
    [l, ..ls], [r, ..rs] ->
      line_diff_loop(ls, rs, [Added(r), Removed(l), ..acc])
  }
}
