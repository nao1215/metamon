//// Generic shrink helpers used by `metamon/generator` to build
//// `Tree(a)`-shaped values for primitive types. Each helper returns a
//// list of "smaller" candidates that the runner will explore in order.

import gleam/list

/// Halve `value` toward `origin`. Returns the empty list when no
/// further progress is possible (e.g. value already equals origin).
///
/// The classic QuickCheck-style shrink: try the origin first, then
/// progressively closer-to-`value` candidates. For example,
/// `int_toward(0, 64)` yields `[0, 32, 48, 56, 60, 62, 63]`. The
/// runner walks this list in order, so the smallest counter-example
/// is found in a single step when `origin` itself triggers the bug.
pub fn int_toward(origin: Int, value: Int) -> List(Int) {
  case value == origin {
    True -> []
    False -> {
      let diff = value - origin
      compute_halves(diff)
      |> list.map(fn(h) { value - h })
      |> dedupe_keeping_first()
    }
  }
}

fn compute_halves(n: Int) -> List(Int) {
  case n == 0 {
    True -> []
    False -> [n, ..compute_halves(n / 2)]
  }
}

fn reverse(items: List(a)) -> List(a) {
  reverse_into(items, [])
}

fn reverse_into(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> reverse_into(rest, [first, ..acc])
  }
}

fn dedupe_keeping_first(items: List(Int)) -> List(Int) {
  dedupe_loop(items, [], [])
}

fn dedupe_loop(items: List(Int), seen: List(Int), acc: List(Int)) -> List(Int) {
  case items {
    [] -> reverse(acc)
    [first, ..rest] ->
      case list.contains(seen, first) {
        True -> dedupe_loop(rest, seen, acc)
        False -> dedupe_loop(rest, [first, ..seen], [first, ..acc])
      }
  }
}

/// Shrink a list by trying progressively smaller drops:
/// drop everything, then drop half, then drop a quarter, etc.
///
/// Returns candidate sub-lists in order from "most aggressive" to
/// "least aggressive" so the runner finds short failing examples first.
pub fn list_drops(items: List(a)) -> List(List(a)) {
  let length = list.length(items)
  drop_at_each_size(items, length, length, [])
  |> reverse()
}

fn drop_at_each_size(
  items: List(a),
  total: Int,
  drop_size: Int,
  acc: List(List(a)),
) -> List(List(a)) {
  case drop_size <= 0 {
    True -> acc
    False -> {
      let new_acc = drop_windows(items, drop_size, total - drop_size, acc)
      drop_at_each_size(items, total, drop_size / 2, new_acc)
    }
  }
}

fn drop_windows(
  items: List(a),
  window: Int,
  remaining_starts: Int,
  acc: List(List(a)),
) -> List(List(a)) {
  case remaining_starts < 0 {
    True -> acc
    False -> {
      let drop_start = remaining_starts
      let candidate = drop_window(items, drop_start, window, [])
      drop_windows(items, window, remaining_starts - window, [candidate, ..acc])
    }
  }
}

fn drop_window(
  items: List(a),
  drop_start: Int,
  drop_count: Int,
  acc: List(a),
) -> List(a) {
  case items, drop_start, drop_count {
    [], _, _ -> reverse(acc)
    [_, ..rest], 0, dc if dc > 0 -> drop_window(rest, 0, dc - 1, acc)
    [first, ..rest], 0, _ -> drop_window(rest, 0, 0, [first, ..acc])
    [first, ..rest], ds, _ ->
      drop_window(rest, ds - 1, drop_count, [first, ..acc])
  }
}
