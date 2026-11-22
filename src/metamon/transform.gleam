//// Named, deterministic input transformations. The `name` is surfaced
//// in failure messages so a metamorphic relation always reports which
//// transformation produced the follow-up input.

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
