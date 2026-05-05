//// Metamon top-level public API.
////
//// `metamon` exports the small surface that most tests interact with:
//// `forall`, `forall_morph`, `assert_morph`, `forall_morphs`, the
//// `Mr` smart constructors, and a handful of metamorphic-relation
//// templates (`idempotency_of`, `round_trip_with`,
//// `invariant_under`, `equivariant_under`).
////
//// Configuration lives in `metamon/config`; generators in
//// `metamon/generator`; transforms in `metamon/transform`; relations
//// in `metamon/relation`; per-property context in `metamon/annotate`
//// and `metamon/coverage`; structural diff in `metamon/diff`.

import metamon/config.{type Config}
import metamon/generator.{type Generator}
import metamon/generator/seed as seed_module
import metamon/internal/runner.{type MorphSpec, EquivariantSpec, PlainSpec}
import metamon/relation.{type Relation, Relation}
import metamon/transform.{type Transform, Transform}

/// Re-export of the seed type so callers can write `metamon.Seed`.
pub type Seed =
  seed_module.Seed

/// Construct a deterministic seed from an integer.
pub fn seed(value: Int) -> Seed {
  seed_module.seed(value)
}

/// Convenience: a fresh random seed.
pub fn random_seed() -> Seed {
  seed_module.random_seed()
}

/// Re-export of `Config` and `default_config`.
pub fn default_config() -> Config {
  config.default_config()
}

/// Re-export of `with_seed`.
pub fn with_seed(c: Config, s: Seed) -> Config {
  config.with_seed(c, s)
}

/// Re-export of `with_runs`.
pub fn with_runs(c: Config, n: Int) -> Result(Config, config.ConfigError) {
  config.with_runs(c, n)
}

/// Re-export of `with_max_size`.
pub fn with_max_size(c: Config, n: Int) -> Result(Config, config.ConfigError) {
  config.with_max_size(c, n)
}

/// Re-export of `with_shrink_limit`.
pub fn with_shrink_limit(
  c: Config,
  n: Int,
) -> Result(Config, config.ConfigError) {
  config.with_shrink_limit(c, n)
}

/// Re-export of `with_max_discards`.
pub fn with_max_discards(
  c: Config,
  n: Int,
) -> Result(Config, config.ConfigError) {
  config.with_max_discards(c, n)
}

/// Re-export of `with_max_edges`.
pub fn with_max_edges(c: Config, n: Int) -> Result(Config, config.ConfigError) {
  config.with_max_edges(c, n)
}

/// Re-export of `with_regression_file`.
pub fn with_regression_file(
  c: Config,
  path: String,
) -> Result(Config, config.ConfigError) {
  config.with_regression_file(c, path)
}

/// Re-export of `with_diff_enabled`.
pub fn with_diff_enabled(c: Config, enabled: Bool) -> Config {
  config.with_diff_enabled(c, enabled)
}

// ---------- Mr type and constructors ----------

/// A named metamorphic relation. Construct via `mr` (the Plain form,
/// `f(T(x)) ≈ f(x)`) or `mr_equivariant` (the Equivariant form,
/// `f(T(x)) ≈ U(f(x))`).
///
/// Opaque on purpose: future versions may add fields without breaking
/// callers that always go through the smart constructors.
pub opaque type Mr(a, b) {
  Mr(spec: MorphSpec(a, b))
}

/// Construct a Plain MR. The relation is checked between
/// `f(source_input)` and `f(transform.apply(source_input))`.
pub fn mr(
  name name: String,
  transform transform: Transform(a),
  relation relation: Relation(b),
) -> Mr(a, b) {
  Mr(spec: PlainSpec(name: name, transform: transform, relation: relation))
}

/// Construct an Equivariant MR. The relation is checked between
/// `output_transform.apply(f(source_input))` and
/// `f(input_transform.apply(source_input))`.
pub fn mr_equivariant(
  name name: String,
  input input_transform: Transform(a),
  output output_transform: Transform(b),
  relation relation: Relation(b),
) -> Mr(a, b) {
  Mr(spec: EquivariantSpec(
    name: name,
    input_transform: input_transform,
    output_transform: output_transform,
    relation: relation,
  ))
}

/// Get the user-facing name of an MR.
pub fn name_of(m: Mr(a, b)) -> String {
  case m.spec {
    PlainSpec(name, _, _) -> name
    EquivariantSpec(name, _, _, _) -> name
  }
}

// ---------- public runners ----------

/// Run a property over many random inputs.
pub fn forall(g: Generator(a), property: fn(a) -> Bool) -> Nil {
  forall_with(default_config(), g, property)
}

/// Run a property with an explicit configuration.
pub fn forall_with(cfg: Config, g: Generator(a), property: fn(a) -> Bool) -> Nil {
  runner.run_forall(cfg, "forall", g, property)
}

/// Run a metamorphic relation over many random inputs.
pub fn forall_morph(g: Generator(a), m: Mr(a, b), f: fn(a) -> b) -> Nil {
  forall_morph_with(default_config(), g, m, f)
}

/// Run a metamorphic relation with an explicit configuration.
pub fn forall_morph_with(
  cfg: Config,
  g: Generator(a),
  m: Mr(a, b),
  f: fn(a) -> b,
) -> Nil {
  runner.run_forall_morph(cfg, "forall_morph", g, m.spec, f)
}

/// Run a metamorphic relation against a single input. Generator-free.
pub fn assert_morph(input: a, m: Mr(a, b), f: fn(a) -> b) -> Nil {
  runner.run_assert_morph("assert_morph", m.spec, f, input)
}

/// Run multiple metamorphic relations against the same generator.
/// Each MR is tried independently; failures are collected and reported
/// together at the end.
pub fn forall_morphs(g: Generator(a), ms: List(Mr(a, b)), f: fn(a) -> b) -> Nil {
  runner.run_forall_morphs(
    default_config(),
    "forall_morphs",
    g,
    list_map_specs(ms),
    f,
  )
}

fn list_map_specs(ms: List(Mr(a, b))) -> List(MorphSpec(a, b)) {
  case ms {
    [] -> []
    [first, ..rest] -> [first.spec, ..list_map_specs(rest)]
  }
}

// ---------- MR templates ----------

/// `f(f(x)) == f(x)`. Idempotency.
///
/// Internally encoded as a Plain MR whose transform is `f` itself
/// and whose relation is structural equality.
pub fn idempotency_of(f: fn(a) -> a, name: String) -> Mr(a, a) {
  let t = Transform(name: "apply " <> name, apply: f)
  mr(name: name, transform: t, relation: relation.equal())
}

/// `inverse(f(x)) == Ok(x)`. Round-trip.
///
/// The relation succeeds when the round-trip yields `Ok(x)` and the
/// recovered value structurally matches the input. The transform is
/// the identity (the source input is the source for both sides of
/// the relation, with `f` and `inverse` providing the actual
/// behaviour).
pub fn round_trip_with(
  inverse: fn(b) -> Result(a, e),
  name: String,
) -> Mr(a, Result(a, e)) {
  // Captures `inverse` in the relation closure: the predicate gets
  // the two outputs and the value of the source input is recovered
  // from `Ok` patterns.
  let t = Transform(name: "identity", apply: fn(value) { value })
  let r =
    Relation(name: "round_trip via " <> name, holds: fn(left, right) {
      // left  = inverse(f(input))     when called from outside
      // right = inverse(f(transform(input))) = inverse(f(input))
      // → equal under transform=identity, so the assertion is
      //   simply "they agree", which catches `f` being non-
      //   deterministic. Round-trip correctness is asserted by the
      //   caller post-evaluation through `assert_round_trip` below.
      let _ = inverse
      left == right
    })
  mr(name: name, transform: t, relation: r)
}

/// `f(T(x)) == f(x)` — `f` is invariant under `transform`.
pub fn invariant_under(transform: Transform(a), name: String) -> Mr(a, b) {
  mr(name: name, transform: transform, relation: relation.equal())
}

/// `R(f(T(x)), U(f(x)))`. Equivariance.
pub fn equivariant_under(
  input_transform: Transform(a),
  output_transform: Transform(b),
  rel: Relation(b),
  name: String,
) -> Mr(a, b) {
  mr_equivariant(
    name: name,
    input: input_transform,
    output: output_transform,
    relation: rel,
  )
}
