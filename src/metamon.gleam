//// Metamon top-level public API.
////
//// `metamon` exports the small surface that most tests interact with:
//// `forall`, `forall_observable`, `forall_morph`, `assert_morph`,
//// `forall_morphs`, `forall_round_trip`, the `Mr` smart constructors,
//// and a handful of metamorphic-relation templates (`idempotency_of`,
//// `invariant_under`, `equivariant_under`, `commutativity_of`).
////
//// Configuration lives in `metamon/config`; generators in
//// `metamon/generator`; transforms in `metamon/transform`; relations
//// in `metamon/relation`; per-property context in `metamon/annotate`
//// and `metamon/coverage`; structural diff in `metamon/diff`.

import metamon/annotate
import metamon/config
import metamon/coverage
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

/// Re-export of `with_runs_or_panic`. Use in test code where the bound
/// is statically known and the `let assert Ok(c) = ...` arm would be
/// dead code.
pub fn with_runs_or_panic(c: Config, n: Int) -> Config {
  config.with_runs_or_panic(c, n)
}

/// Re-export of `with_max_size_or_panic`.
pub fn with_max_size_or_panic(c: Config, n: Int) -> Config {
  config.with_max_size_or_panic(c, n)
}

/// Re-export of `with_shrink_limit_or_panic`.
pub fn with_shrink_limit_or_panic(c: Config, n: Int) -> Config {
  config.with_shrink_limit_or_panic(c, n)
}

/// Re-export of `with_max_edges_or_panic`.
pub fn with_max_edges_or_panic(c: Config, n: Int) -> Config {
  config.with_max_edges_or_panic(c, n)
}

/// Re-export of `with_regression_file_or_panic`.
pub fn with_regression_file_or_panic(c: Config, path: String) -> Config {
  config.with_regression_file_or_panic(c, path)
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

/// Run a property whose predicate also exposes its intermediate value.
///
/// `predicate` returns `#(observation, holds)`. `holds` decides whether
/// the property is satisfied (same as `forall`); `observation` is
/// recorded under the label `predicate value` and shown in the failure
/// report — no manual `annotate.annotate_value` is needed.
///
/// Use this when the predicate's intermediate value (typically `f(input)`)
/// is what determines the branch. Without it, `forall` failure reports
/// only show the shrunk source input, which can force a debug round-trip
/// to recover what `f(input)` actually was.
pub fn forall_observable(g: Generator(a), predicate: fn(a) -> #(b, Bool)) -> Nil {
  forall_observable_with(default_config(), g, predicate)
}

/// `forall_observable` with an explicit configuration.
pub fn forall_observable_with(
  cfg: Config,
  g: Generator(a),
  predicate: fn(a) -> #(b, Bool),
) -> Nil {
  runner.run_forall(cfg, "forall_observable", g, fn(input) {
    let #(observed, holds) = predicate(input)
    annotate.annotate_value("predicate value", observed)
    holds
  })
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
///
/// Passing `[]` for `transforms` is a programming error (vacuous test)
/// and panics with a structured message.
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
///
/// Passing `[]` is a programming error (vacuous test) and panics with
/// a structured message — use `forall(...)` for a single-input property.
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
  runner.run_forall(cfg, "round_trip[" <> name <> "]", gen, fn(input) {
    case decode(encode(input)) {
      Ok(decoded) -> decoded == input
      Error(_) -> False
    }
  })
}

/// Run a round-trip property where the encoder is partial: the
/// encoder returns `Result(b, e_enc)` because not every generated
/// input is a valid input for the codec. Inputs the encoder rejects
/// (`Error(_)`) are treated as out of scope and skipped — the
/// property succeeds for them.
///
/// Use this variant for codecs whose encoder has structural
/// preconditions: byte-alignment requirements, value-range checks,
/// hrp / version constraints, etc. A typical pattern is to combine
/// `forall_round_trip_partial` with a generator that produces the
/// surrounding inputs (e.g. arbitrary `BitArray` plus arbitrary
/// version bytes); the encoder filters down to the valid subset and
/// the property checks the round-trip on that subset.
///
/// The failure report header is `round_trip[<name>]` so it is
/// immediately obvious from the panic which round-trip broke. The
/// underlying machinery is the same as `forall`, including shrinking
/// of the source input.
///
/// ```gleam
/// metamon.forall_round_trip_partial(
///   gen: generator.tuple2(byte_gen, payload_gen),
///   name: "base58check",
///   encode: fn(pair) { base58check.encode(pair.0, pair.1) },
///   decode: fn(s) {
///     case base58check.decode(s) {
///       Ok(decoded) -> Ok(#(decoded.version, decoded.payload))
///       Error(e) -> Error(e)
///     }
///   },
/// )
/// ```
pub fn forall_round_trip_partial(
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> Result(b, e_enc),
  decode decode: fn(b) -> Result(a, e_dec),
) -> Nil {
  forall_round_trip_partial_with(
    cfg: default_config(),
    gen: gen,
    name: name,
    encode: encode,
    decode: decode,
  )
}

/// `forall_round_trip_partial` with an explicit configuration.
///
/// The runner automatically registers a `coverage.cover_at_least(1,
/// "encoder_accepted", ok)` requirement so a property whose generator
/// is so wide that the encoder rejects every sample fails the test
/// with a structured "coverage shortfall" message rather than passing
/// silently. To enforce a stricter floor (e.g. "at least 50% of
/// inputs must round-trip"), call
/// `coverage.cover(50.0, "encoder_accepted", ok)` inside your own
/// property body — coverage labels accumulate across calls.
pub fn forall_round_trip_partial_with(
  cfg cfg: Config,
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> Result(b, e_enc),
  decode decode: fn(b) -> Result(a, e_dec),
) -> Nil {
  runner.run_forall(cfg, "round_trip[" <> name <> "]", gen, fn(input) {
    case encode(input) {
      // The encoder declared this input out of scope. Skip it: the
      // property is vacuously true for inputs the codec does not
      // accept. The cover_at_least(1, ...) requirement below ensures
      // the runner panics with a "coverage shortfall" if every input
      // is rejected, so a 100%-rejection generator does not silently
      // pass.
      Error(_) -> {
        coverage.cover_at_least(1, "encoder_accepted", False)
        True
      }
      Ok(encoded) -> {
        coverage.cover_at_least(1, "encoder_accepted", True)
        case decode(encoded) {
          Ok(decoded) -> decoded == input
          Error(_) -> False
        }
      }
    }
  })
}

/// Run a round-trip property using a caller-supplied equality
/// `Relation(a)` instead of structural `==`. The decoded value must
/// satisfy `equality.holds(decoded, input)`.
///
/// Use this when the source type carries values that are not
/// preserved verbatim across encode → decode: opaque types whose
/// decoded form normalises (e.g. multipart `Part` with re-derived
/// convenience fields), MIME types that lowercase the essence, JSON
/// values whose key order is implementation-defined. Composing with
/// `relation.equivalent_under(via, name)` lets you compare on a
/// projection (e.g. `headers + body` ignoring derived caches).
///
/// The failure report header is `round_trip[<name>]`. The relation's
/// own `name` appears under `relation:` in the failure block, just
/// like `forall_morph` failures.
///
/// ```gleam
/// metamon.forall_round_trip_under(
///   gen: parts_gen(),
///   name: "multipart_round_trip",
///   encode: fn(parts) { multipartkit.encode(boundary, parts) },
///   decode: fn(body) { multipartkit.parse(body, content_type) },
///   equality: relation.equivalent_under(
///     fn(parts) { list.map(parts, part_payload) },
///     "wire_payload",
///   ),
/// )
/// ```
pub fn forall_round_trip_under(
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
  equality equality: Relation(a),
) -> Nil {
  forall_round_trip_under_with(
    cfg: default_config(),
    gen: gen,
    name: name,
    encode: encode,
    decode: decode,
    equality: equality,
  )
}

/// `forall_round_trip_under` with an explicit configuration.
pub fn forall_round_trip_under_with(
  cfg cfg: Config,
  gen gen: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
  equality equality: Relation(a),
) -> Nil {
  runner.run_forall(cfg, "round_trip[" <> name <> "]", gen, fn(input) {
    case decode(encode(input)) {
      Ok(decoded) -> equality.holds(decoded, input)
      Error(_) -> False
    }
  })
}
