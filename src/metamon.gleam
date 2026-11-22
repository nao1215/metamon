//// Metamon top-level public API.
////
//// `metamon` exports the small surface that most tests interact with:
//// `forall`, `forall_morph`, `assert_morph`,
//// `forall_morphs`, `forall_round_trip`, the `Mr` smart constructors,
//// and a handful of metamorphic-relation templates (`idempotency_of`,
//// `invariant_under`, `equivariant_under`, `commutativity_of`).
////
//// Configuration lives in `metamon/config`; generators in
//// `metamon/generator`; transforms in `metamon/transform`; relations
//// in `metamon/relation`; per-property context in `metamon/annotate`
//// and `metamon/coverage`.

import gleam/list
import gleam/option.{type Option, None}
import metamon/generator.{type Generator}
import metamon/internal/runner.{type MorphSpec}
import metamon/relation.{type Relation}
import metamon/transform.{type Transform}

/// How a runner explores inputs and reports a failure. Build one from
/// `default_config` and override the fields you need:
///
/// ```gleam
/// let config = metamon.Config(..metamon.default_config(), runs: 300)
/// ```
///
/// The runners check the fields when they start; see `forall_with` for
/// the values they reject.
pub type Config {
  Config(
    /// The number of inputs to try. `METAMON_RUNS_MULTIPLIER`, when set to
    /// a positive integer, multiplies it.
    runs: Int,
    /// The seed of the random inputs. `None` draws a new seed for every
    /// property; `Some(n)` replays the same inputs on every run.
    seed: Option(Int),
    /// The largest size given to the generators. Sizes grow from `0` on
    /// the first run to `max_size` on the last.
    max_size: Int,
    /// The largest number of shrink steps taken on one failure.
    shrink_limit: Int,
    /// The largest number of edge values tried before the random inputs.
    max_edges: Int,
    /// A file that records every failing input and replays the recorded
    /// inputs first on the next run. `None` turns recording off. Use one
    /// file per plain `forall` property: every plain property records
    /// under the same key, so a shared file replays one property's
    /// failures against another.
    regression_file: Option(String),
    /// The format of the failure report.
    output: Output,
  )
}

/// The format of a failure report.
pub type Output {
  /// A multi-line report for people (the default).
  Text
  /// A single-line JSON object for CI and other tools.
  Json
}

/// Return the default configuration: 100 runs, a new random seed for
/// every property, `max_size` 99, at most 1024 shrink steps, at most 16
/// edge values, no regression file and text output.
pub fn default_config() -> Config {
  Config(
    runs: 100,
    seed: None,
    max_size: 99,
    shrink_limit: 1024,
    max_edges: 16,
    regression_file: None,
    output: Text,
  )
}

/// The runner settings for `config`. Panics when a field is invalid.
fn settings(config: Config) -> runner.Settings {
  runner.settings(
    runs: config.runs,
    seed: config.seed,
    max_size: config.max_size,
    shrink_limit: config.shrink_limit,
    max_edges: config.max_edges,
    regression_file: config.regression_file,
    json: config.output == Json,
  )
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
pub fn forall_with(
  cfg: Config,
  g: Generator(a),
  property: fn(a) -> Bool,
) -> Nil {
  runner.run_forall(settings(cfg), "forall", "(plain property)", g, property)
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
  runner.run_forall_morph(settings(cfg), "forall_morph", g, m.spec, f)
}

/// Run a metamorphic relation against a single input. Generator-free.
pub fn assert_morph(input: a, m: Mr(a, b), f: fn(a) -> b) -> Nil {
  runner.run_assert_morph("assert_morph", m.spec, f, input)
}

/// Run multiple metamorphic relations against the same generator.
/// Each MR is tried independently; failures are collected and reported
/// together at the end.
///
/// Passing `[]` is a programming error (vacuous test) and panics with
/// a structured message — use `forall(...)` for a single-input property.
pub fn forall_morphs(
  g: Generator(a),
  ms: List(Mr(a, b)),
  f: fn(a) -> b,
) -> Nil {
  runner.run_forall_morphs(
    settings(default_config()),
    "forall_morphs",
    g,
    list.map(ms, fn(m) { m.spec }),
    f,
  )
}

// ---------- MR templates ----------
//
// All templates take `name` first and use labelled arguments so the
// call sites read naturally:
//
//   metamon.idempotency_of(name: "trim", of: string.trim)
//   metamon.invariant_under(name: "len_under_reverse", under: reverse)
//
// Round-trip is not exposed as a Plain MR — MR's two-point output
// relation cannot express the source-vs-output comparison
// `decode(encode(x)) == Ok(x)`. Instead, the runner-style helper
// `forall_round_trip` (below) wraps `forall` with a named header
// (`round_trip[<name>]`) so the failure report identifies which
// round-trip broke, which is the discoverability win without forcing
// a contrived MR shape.

/// `f(f(x)) == f(x)`. Idempotency.
///
/// Encoded as a Plain MR whose transform is `f` itself and whose
/// relation is structural equality.
pub fn idempotency_of(name name: String, of f: fn(a) -> a) -> Mr(a, a) {
  let apply_t = transform.new("apply " <> name, f)
  mr(name: name, transform: apply_t, relation: relation.equal())
}

/// `f(T(x)) == f(x)` — `f` is invariant under the input transform.
pub fn invariant_under(
  name name: String,
  under under: Transform(a),
) -> Mr(a, b) {
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
/// let mr = metamon.commutativity_of(name: "add_commutative")
/// metamon.forall_morph(
///   generator.tuple2(int_gen, int_gen),
///   mr,
///   fn(pair) { add(pair.0, pair.1) },
/// )
/// ```
pub fn commutativity_of(name name: String) -> Mr(#(a, a), b) {
  let swap = transform.new("swap", fn(pair: #(a, a)) { #(pair.1, pair.0) })
  mr(name: name, transform: swap, relation: relation.equal())
}

/// Run a round-trip property over many random inputs:
/// `decode(encode(x))` must equal `Ok(x)` for every generated `x`.
///
/// The failure report header is `round_trip[<name>]` so it is
/// immediately obvious from the panic which round-trip broke. The
/// underlying machinery is the same as `forall`, including shrinking
/// of the source input.
///
/// ```gleam
/// metamon.forall_round_trip(
///   gen: generator.bit_array(range.constant(0, 16)),
///   name: "base64",
///   encode: base64.encode,
///   decode: base64.decode,
/// )
/// ```
pub fn forall_round_trip(
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
) -> Nil {
  forall_round_trip_with(
    cfg: default_config(),
    gen: gen,
    name: name,
    encode: encode,
    decode: decode,
  )
}

/// `forall_round_trip` with an explicit configuration.
pub fn forall_round_trip_with(
  cfg cfg: Config,
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
) -> Nil {
  run_round_trip(
    cfg,
    name,
    gen,
    decodes_back(encode, decode, fn(decoded, input) { decoded == input }),
  )
}

/// Run `property` under the round-trip name, which is both the report's
/// test name and the regression key.
fn run_round_trip(
  cfg: Config,
  name: String,
  gen: Generator(a),
  property: fn(a) -> Bool,
) -> Nil {
  let test_name = "round_trip[" <> name <> "]"
  runner.run_forall(settings(cfg), test_name, test_name, gen, property)
}

/// `decode(encode(input))` succeeds and `equal(decoded, input)` holds.
fn decodes_back(
  encode: fn(a) -> b,
  decode: fn(b) -> Result(a, e),
  equal: fn(a, a) -> Bool,
) -> fn(a) -> Bool {
  fn(input) {
    case decode(encode(input)) {
      Ok(decoded) -> equal(decoded, input)
      Error(_) -> False
    }
  }
}
