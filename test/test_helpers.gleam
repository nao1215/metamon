/// Generate `[start, start + 1, ..., start + count - 1]`.
///
/// Replacement for `gleam/list.range/2` whose availability depends on
/// the stdlib version pinned in `manifest.toml`. Tests use this so they
/// stay portable across stdlib bumps.
pub fn integers_from(start: Int, count: Int) -> List(Int) {
  build_integers(start, count, [])
  |> reverse_list()
}

fn build_integers(start: Int, count: Int, acc: List(Int)) -> List(Int) {
  case count <= 0 {
    True -> acc
    False -> build_integers(start + 1, count - 1, [start, ..acc])
  }
}

fn reverse_list(items: List(a)) -> List(a) {
  reverse_into(items, [])
}

fn reverse_into(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> reverse_into(rest, [first, ..acc])
  }
}
