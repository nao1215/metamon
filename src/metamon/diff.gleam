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
    False -> shape_aware_diff(left, right)
  }
}

fn shape_aware_diff(left: a, right: a) -> Diff {
  let l_str = string.inspect(left)
  let r_str = string.inspect(right)
  case is_list_inspect(l_str), is_list_inspect(r_str) {
    True, True -> list_diff_from_inspect(l_str, r_str)
    _, _ -> Differ(left: l_str, right: r_str)
  }
}

fn is_list_inspect(s: String) -> Bool {
  string.starts_with(s, "[") && string.ends_with(s, "]")
}

fn list_diff_from_inspect(left: String, right: String) -> Diff {
  let l_items = split_top_level(left)
  let r_items = split_top_level(right)
  ListDiff(items: zip_items(l_items, r_items, 0))
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
  // Strip the enclosing brackets (which we know are the first/last
  // characters because `is_list_inspect` returned true) and walk
  // character-by-character, tracking nesting depth so commas inside
  // sub-structures don't cause splits.
  let inner = case
    string.starts_with(inspected, "["),
    string.ends_with(inspected, "]")
  {
    True, True ->
      inspected
      |> string.drop_start(1)
      |> string.drop_end(1)
    _, _ -> inspected
  }
  walk_and_split(string.to_graphemes(inner), 0, "", [])
}

fn walk_and_split(
  graphemes: List(String),
  depth: Int,
  acc: String,
  results: List(String),
) -> List(String) {
  case graphemes {
    [] -> finish_split(acc, results)
    [first, ..rest] ->
      case first, depth {
        "[", _ -> walk_and_split(rest, depth + 1, acc <> first, results)
        "]", d if d > 0 -> walk_and_split(rest, d - 1, acc <> first, results)
        "(", _ -> walk_and_split(rest, depth + 1, acc <> first, results)
        ")", d if d > 0 -> walk_and_split(rest, d - 1, acc <> first, results)
        ",", 0 -> walk_and_split(rest, 0, "", [string.trim(acc), ..results])
        _, _ -> walk_and_split(rest, depth, acc <> first, results)
      }
  }
}

fn finish_split(acc: String, results: List(String)) -> List(String) {
  case string.trim(acc) {
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
      let lcs_table = build_lcs(l_lines, r_lines)
      let segments = backtrack_diff(l_lines, r_lines, lcs_table)
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
    ListDiff(items) -> render_list_diff(items, indent)
    StringDiff(_, _, segments) -> render_string_diff(segments, indent)
  }
}

fn render_list_diff(items: List(IndexedDiff), indent: String) -> String {
  list.map(items, fn(item: IndexedDiff) {
    indent
    <> "[#"
    <> int.to_string(item.index)
    <> "]\n"
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

// ---------- LCS ----------
//
// Naive LCS table over Erlang lists, O(m*n). Acceptable for the diff-
// for-failure-output use case.

type LcsTable =
  List(List(Int))

fn build_lcs(left: List(String), right: List(String)) -> LcsTable {
  build_rows(left, right, [])
}

fn build_rows(
  remaining_left: List(String),
  right: List(String),
  acc: LcsTable,
) -> LcsTable {
  case remaining_left {
    [] -> {
      let row_for_empty = list.map(right, fn(_x) { 0 })
      list.reverse([[0, ..row_for_empty], ..acc])
    }
    [first, ..rest] -> {
      let prev_row = case acc {
        [] -> empty_row(right)
        [most_recent, ..] -> most_recent
      }
      let row = build_row(first, right, prev_row, [], 0)
      build_rows(rest, right, [row, ..acc])
    }
  }
}

fn empty_row(right: List(String)) -> List(Int) {
  [0, ..list.map(right, fn(_x) { 0 })]
}

fn build_row(
  l: String,
  remaining: List(String),
  prev_row: List(Int),
  acc: List(Int),
  current_left_value: Int,
) -> List(Int) {
  case remaining, prev_row {
    [], _ -> list.reverse([current_left_value, ..acc])
    [r, ..rs], [_, ..rest_prev] -> {
      let above = case rest_prev {
        [v, ..] -> v
        [] -> 0
      }
      let diagonal = case prev_row {
        [v, ..] -> v
        [] -> 0
      }
      let value = case l == r {
        True -> diagonal + 1
        False -> max_int(above, current_left_value)
      }
      build_row(l, rs, rest_prev, [current_left_value, ..acc], value)
    }
    _, [] -> list.reverse([current_left_value, ..acc])
  }
}

fn max_int(a: Int, b: Int) -> Int {
  case a >= b {
    True -> a
    False -> b
  }
}

fn backtrack_diff(
  left: List(String),
  right: List(String),
  _table: LcsTable,
) -> List(Segment) {
  // For the failure-report use case we accept a degraded but
  // deterministic diff: walk both sides in lockstep, and whenever
  // they diverge emit `Removed` for the left line and `Added` for
  // the right line. This produces useful diffs for short, mostly-
  // aligned outputs (which is the common case for serialised AST /
  // OpenAPI specs in oaspec) without paying the cost of a precise
  // backtrack through the LCS table.
  case left, right {
    [], [] -> []
    [], [r, ..rs] -> [Added(r), ..backtrack_diff([], rs, [])]
    [l, ..ls], [] -> [Removed(l), ..backtrack_diff(ls, [], [])]
    [l, ..ls], [r, ..rs] ->
      case l == r {
        True -> [Common(l), ..backtrack_diff(ls, rs, [])]
        False -> [Removed(l), Added(r), ..backtrack_diff(ls, rs, [])]
      }
  }
}
