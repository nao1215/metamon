//// Named, deterministic input transformations. The `name` is surfaced
//// in failure messages so a metamorphic relation always reports which
//// transformation produced the follow-up input.

import gleam/int

/// A named, deterministic function `a -> a`.
///
/// `name` is shown in failure output. `apply` must be pure: same input,
/// same output, no side effects.
pub type Transform(a) {
  Transform(name: String, apply: fn(a) -> a)
}

/// Construct a transform from a name and a function.
pub fn new(name: String, apply: fn(a) -> a) -> Transform(a) {
  Transform(name: name, apply: apply)
}

/// The transform that returns its input unchanged.
pub fn identity() -> Transform(a) {
  Transform(name: "identity", apply: fn(value) { value })
}

/// A transform that ignores its input and always returns `value`.
/// Use sparingly — most metamorphic relations want a real
/// transformation rather than a constant.
pub fn always(name: String, value: a) -> Transform(a) {
  Transform(name: name, apply: fn(_input) { value })
}

/// Sequential composition: `then(t1, t2).apply(x) == t2.apply(t1.apply(x))`.
/// The composite name is `"<t1.name> |> <t2.name>"`.
pub fn then(t1: Transform(a), t2: Transform(a)) -> Transform(a) {
  Transform(name: t1.name <> " |> " <> t2.name, apply: fn(value) {
    t2.apply(t1.apply(value))
  })
}

/// Apply `t` exactly `n` times. `repeat(t, 0)` is `identity`. Negative
/// counts are treated as `0`.
pub fn repeat(t: Transform(a), times n: Int) -> Transform(a) {
  case n <= 0 {
    True -> identity()
    False ->
      Transform(
        name: t.name <> " × " <> int.to_string(n),
        apply: repeat_apply(t.apply, n),
      )
  }
}

fn repeat_apply(f: fn(a) -> a, times: Int) -> fn(a) -> a {
  fn(value) { repeat_step(f, times, value) }
}

fn repeat_step(f: fn(a) -> a, remaining: Int, value: a) -> a {
  case remaining <= 0 {
    True -> value
    False -> repeat_step(f, remaining - 1, f(value))
  }
}

/// Override the name of a transform. The behaviour of `apply` is not
/// changed — only the label that appears in failure reports.
pub fn rename(t: Transform(a), name: String) -> Transform(a) {
  Transform(name: name, apply: t.apply)
}
