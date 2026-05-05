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

import metamon/config
import metamon/generator.{type Generator}
import metamon/generator/seed as seed_module
import metamon/internal/runner.{type MorphSpec}
import metamon/relation.{type Relation}
import metamon/transform.{type Transform}

/// Re-export of the seed type so callers can write `metamon.Seed`.
pub type Seed =
  seed_module.Seed

/// Re-export of `Config` so callers can write `metamon.Config`.
pub type Config =
  config.Config

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

/// Re-export of `OutputFormat` so callers can write
/// `metamon.OutputFormat`.
pub type OutputFormat =
  config.OutputFormat

/// Choose the failure-report output format. `Text` (default) is
/// human-friendly; `Json` is single-line JSON for CI / LLM consumers.
pub fn with_output_format(c: Config, fmt: OutputFormat) -> Config {
  config.with_output_format(c, fmt)
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
  Mr(spec: runner.plain(name, transform, relation))
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
  Mr(spec: runner.equivariant(name, input_transform, output_transform, relation))
}

/// Get the user-facing name of an MR.
pub fn name_of(m: Mr(a, b)) -> String {
  runner.morph_name(m.spec)
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

/// Run an N-ary metamorphic relation: apply each of `transforms` to
/// the source input to build follow-up inputs, then assert that the
/// resulting outputs `[f(x), f(T0(x)), ..., f(Tn(x))]` satisfy
/// `relation`. Useful when the property requires comparing more than
/// two outputs in one shot (e.g. `(a, b, c) ↦ op(op(a,b), c)` and its
/// re-associations all agree).
pub fn forall_morph_n(
  g: Generator(a),
  transforms: List(Transform(a)),
  rel: relation.RelationN(b),
  f: fn(a) -> b,
) -> Nil {
  forall_morph_n_with(default_config(), g, transforms, rel, f)
}

/// `forall_morph_n` with an explicit configuration.
pub fn forall_morph_n_with(
  cfg: Config,
  g: Generator(a),
  transforms: List(Transform(a)),
  rel: relation.RelationN(b),
  f: fn(a) -> b,
) -> Nil {
  runner.run_forall_morph_n(cfg, "forall_morph_n", g, transforms, rel, f)
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
//
// All templates take `name` first and use labelled arguments so the
// call sites read naturally:
//
//   metamon.idempotency_of(name: "trim", of: string.trim)
//   metamon.invariant_under(name: "len_under_reverse", under: list_t.reverse())
//
// Round-trip is intentionally NOT a template: the textbook
// `parse(write(x)) == Ok(x)` is a single-input invariant and is
// expressed more directly with `metamon.forall` than as an MR.
// See README "Round-trip" section for the canonical pattern.

/// `f(f(x)) == f(x)`. Idempotency.
///
/// Encoded as a Plain MR whose transform is `f` itself and whose
/// relation is structural equality.
pub fn idempotency_of(name name: String, of f: fn(a) -> a) -> Mr(a, a) {
  let t = transform.new("apply " <> name, f)
  mr(name: name, transform: t, relation: relation.equal())
}

/// `f(T(x)) == f(x)` — `f` is invariant under the input transform.
pub fn invariant_under(name name: String, under under: Transform(a)) -> Mr(a, b) {
  mr(name: name, transform: under, relation: relation.equal())
}

/// `R(U(f(x)), f(T(x)))`. Equivariance: the input transform `T` and
/// the output transform `U` commute with `f` modulo `R`.
pub fn equivariant_under(
  name name: String,
  input input_transform: Transform(a),
  output output_transform: Transform(b),
  relation rel: Relation(b),
) -> Mr(a, b) {
  mr_equivariant(
    name: name,
    input: input_transform,
    output: output_transform,
    relation: rel,
  )
}

/// `op(a, b) == op(b, a)` — `op` is commutative.
///
/// The MR is over the input pair `#(a, a)` and the output type `b`.
/// Use it as:
///
/// ```gleam
/// let mr = metamon.commutativity_of(name: "add_commutative", of: add)
/// metamon.forall_morph(
///   generator.tuple2(int_gen, int_gen),
///   mr,
///   fn(pair) { add(pair.0, pair.1) },
/// )
/// ```
pub fn commutativity_of(
  name name: String,
  of _op: fn(a, a) -> b,
) -> Mr(#(a, a), b) {
  let swap = transform.new("swap", fn(pair: #(a, a)) { #(pair.1, pair.0) })
  mr(name: name, transform: swap, relation: relation.equal())
}
