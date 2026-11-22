//// Property-based and metamorphic testing.
////
//// `forall` runs a property on many generated inputs and shrinks the
//// first input that makes it panic. `forall_morph` checks metamorphic
//// relations: how the output of a function changes when its input is
//// transformed. Generators live in `metamon/generator`.
////
//// ```gleam
//// import gleam/list
//// import metamon
//// import metamon/generator
////
//// pub fn reverse_twice_test() {
////   let lists =
////     generator.list_of(
////       generator.int(generator.range(from: -100, to: 100)),
////       length: generator.range(from: 0, to: 20),
////     )
////   metamon.forall(lists, fn(items) {
////     assert list.reverse(list.reverse(items)) == items
////   })
//// }
//// ```

import gleam/float
import gleam/list
import gleam/option.{type Option, None}
import metamon/generator.{type Generator}
import metamon/internal/annotate as annotation
import metamon/internal/coverage
import metamon/internal/report
import metamon/internal/runner

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

/// A named transformation of an input, such as reversing a list. The
/// name appears in failure reports. `apply` must be pure.
pub type Transform(a) {
  Transform(name: String, apply: fn(a) -> a)
}

/// A named check between two outputs, such as equality. The name appears
/// in failure reports.
pub type Relation(b) {
  Relation(name: String, holds: fn(b, b) -> Bool)
}

/// A metamorphic relation of a function `f` from `a` to `b`. The name
/// identifies the morph in failure reports and in the regression file.
pub type Morph(a, b) {
  /// `f(x)` and `f(transform.apply(x))` satisfy `relation`.
  Morph(name: String, transform: Transform(a), relation: Relation(b))
  /// `output.apply(f(x))` and `f(input.apply(x))` satisfy `relation`:
  /// transforming the input transforms the output the same way.
  Equivariant(
    name: String,
    input: Transform(a),
    output: Transform(b),
    relation: Relation(b),
  )
}

/// Run `property` on many generated inputs. The property fails when it
/// panics: a failing `assert` or `let assert`, a `panic`, or an Erlang
/// error or JavaScript exception. On failure the input is shrunk to a
/// smaller one that still panics, and the runner panics with a report of
/// that input and its panic message.
///
/// ```gleam
/// metamon.forall(generator.int(generator.range(from: -100, to: 100)), fn(n) {
///   assert n + 0 == n
/// })
/// ```
pub fn forall(generator: Generator(a), property: fn(a) -> Nil) -> Nil {
  forall_with(default_config(), generator, property)
}

/// Run `property` like `forall`, with an explicit configuration.
///
/// ## Panics
///
/// Panics when `config.runs`, `config.max_size`, `config.shrink_limit` or
/// `config.max_edges` is not positive, or `config.regression_file` is
/// `Some("")`. Every runner that takes a `Config` checks it the same way.
pub fn forall_with(
  config: Config,
  generator: Generator(a),
  property: fn(a) -> Nil,
) -> Nil {
  runner.run_forall(
    settings(config),
    "forall",
    "(plain property)",
    generator,
    property,
  )
}

/// Check every morph in `morphs` against `function` on many generated
/// inputs. Each morph runs on its own; when any fails, the input is
/// shrunk and the runner panics with the report of every failing morph.
///
/// ```gleam
/// let lists =
///   generator.list_of(
///     generator.int(generator.range(from: 0, to: 9)),
///     length: generator.range(from: 0, to: 10),
///   )
/// let reverse = metamon.Transform(name: "reverse", apply: list.reverse)
/// metamon.forall_morph(
///   lists,
///   [metamon.invariant_under(name: "sum_under_reverse", under: reverse)],
///   int.sum,
/// )
/// ```
///
/// ## Panics
///
/// Panics when `morphs` is empty.
pub fn forall_morph(
  generator: Generator(a),
  morphs: List(Morph(a, b)),
  function: fn(a) -> b,
) -> Nil {
  forall_morph_with(default_config(), generator, morphs, function)
}

/// Check `morphs` like `forall_morph`, with an explicit configuration.
///
/// ## Panics
///
/// Panics when `morphs` is empty, or when `config` is invalid as
/// described in `forall_with`.
pub fn forall_morph_with(
  config: Config,
  generator: Generator(a),
  morphs: List(Morph(a, b)),
  function: fn(a) -> b,
) -> Nil {
  runner.run_forall_morph(
    settings(config),
    "forall_morph",
    generator,
    list.map(morphs, spec),
    function,
  )
}

/// Check `morph` against `function` on the single input `input`, for
/// example a shrunk input copied from a failure report. Panics with a
/// report when the relation does not hold.
pub fn assert_morph(input: a, morph: Morph(a, b), function: fn(a) -> b) -> Nil {
  runner.run_assert_morph("assert_morph", spec(morph), function, input)
}

fn spec(morph: Morph(a, b)) -> runner.MorphSpec(a, b) {
  case morph {
    Morph(name:, transform:, relation:) ->
      runner.MorphSpec(
        name: name,
        mode: report.Plain(transform_name: transform.name),
        follow_up: transform.apply,
        expected: fn(output) { output },
        relation_name: relation.name,
        holds: relation.holds,
      )
    Equivariant(name:, input:, output:, relation:) ->
      runner.MorphSpec(
        name: name,
        mode: report.Equivariant(
          input_transform_name: input.name,
          output_transform_name: output.name,
        ),
        follow_up: input.apply,
        expected: output.apply,
        relation_name: relation.name,
        holds: relation.holds,
      )
  }
}

/// Check that `decode(encode(x))` is `Ok(x)` for many generated `x`.
/// The report is titled `round_trip[<name>]`, and a failing input is
/// shrunk like in `forall`.
///
/// ```gleam
/// metamon.forall_round_trip(
///   generator: generator.int(generator.range(from: -1000, to: 1000)),
///   name: "int_to_string",
///   encode: int.to_string,
///   decode: int.parse,
/// )
/// ```
pub fn forall_round_trip(
  generator generator: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
) -> Nil {
  forall_round_trip_with(
    config: default_config(),
    generator: generator,
    name: name,
    encode: encode,
    decode: decode,
  )
}

/// Check a round trip like `forall_round_trip`, with an explicit
/// configuration.
///
/// ## Panics
///
/// Panics when `config` is invalid as described in `forall_with`.
pub fn forall_round_trip_with(
  config config: Config,
  generator generator: Generator(a),
  name name: String,
  encode encode: fn(a) -> b,
  decode decode: fn(b) -> Result(a, e),
) -> Nil {
  runner.run_round_trip(settings(config), name, generator, encode, decode)
}

/// Count the current run as hitting `label` when `condition` is true. A
/// label counts at most once per run. The counts appear in the coverage
/// part of a failure report.
///
/// ```gleam
/// metamon.forall(lists, fn(items) {
///   metamon.classify(label: "empty", when: items == [])
///   assert list.reverse(list.reverse(items)) == items
/// })
/// ```
pub fn classify(label label: String, when condition: Bool) -> Nil {
  coverage.classify(label, condition)
}

/// Like `classify`, and require at least `percent` percent of the runs
/// to hit `label`. When fewer do, the property fails after its last run
/// with a coverage shortfall, even if every run passed.
///
/// ## Panics
///
/// Panics when `percent` is outside `[0.0, 100.0]` or NaN.
pub fn cover(
  at_least percent: Float,
  label label: String,
  when condition: Bool,
) -> Nil {
  coverage.cover(percent, label, condition)
}

/// Record `value` under `label` for the current run. The failure report
/// shows the values recorded in the run of the reported input, rendered
/// with `string.inspect`; a passing run discards them.
///
/// ```gleam
/// metamon.forall(ints, fn(n) {
///   let doubled = n * 2
///   metamon.annotate(label: "doubled", value: doubled)
///   assert doubled >= n
/// })
/// ```
pub fn annotate(label label: String, value value: a) -> Nil {
  annotation.annotate(label, value)
}

/// Return the morph `f(f(x)) == f(x)`: applying `function` twice gives
/// the same output as applying it once. Use it as the morph of `function`
/// itself.
pub fn idempotency_of(
  name name: String,
  of function: fn(a) -> a,
) -> Morph(a, a) {
  Morph(
    name: name,
    transform: Transform(name: "apply " <> name, apply: function),
    relation: equal(),
  )
}

/// Return the morph `f(transform.apply(x)) == f(x)`: the output does not
/// change when the input is transformed.
pub fn invariant_under(
  name name: String,
  under transform: Transform(a),
) -> Morph(a, b) {
  Morph(name: name, transform: transform, relation: equal())
}

/// Return the morph `f(#(a, b)) == f(#(b, a))` for a function of a pair:
/// swapping the arguments does not change the output.
pub fn commutativity_of(name name: String) -> Morph(#(a, a), b) {
  Morph(
    name: name,
    transform: Transform(name: "swap", apply: fn(pair: #(a, a)) {
      #(pair.1, pair.0)
    }),
    relation: equal(),
  )
}

/// Return the relation that holds when both outputs are equal with `==`.
pub fn equal() -> Relation(a) {
  Relation(name: "equal", holds: fn(left, right) { left == right })
}

/// Return the relation that holds when two floats differ by at most
/// `epsilon`.
///
/// ## Panics
///
/// Panics when `epsilon` is negative, since no pair of floats would then
/// satisfy the relation.
pub fn approximately(within epsilon: Float) -> Relation(Float) {
  case epsilon <. 0.0 {
    True ->
      panic as "metamon.approximately: epsilon must be >= 0.0 (a negative epsilon would make every pair compare False, including a value with itself)"
    False ->
      Relation(
        name: "approximately(" <> float.to_string(epsilon) <> ")",
        holds: fn(left, right) {
          let difference = case left >=. right {
            True -> left -. right
            False -> right -. left
          }
          difference <=. epsilon
        },
      )
  }
}

/// Return the relation that holds when both outputs are equal after
/// `project`, such as equal ignoring case. The report names it
/// `equivalent_under(<name>)`.
pub fn equivalent_under(
  name name: String,
  via project: fn(b) -> c,
) -> Relation(b) {
  Relation(name: "equivalent_under(" <> name <> ")", holds: fn(left, right) {
    project(left) == project(right)
  })
}

/// Return the relation that holds when two lists have the same elements
/// with the same counts, in any order.
pub fn permutation_of() -> Relation(List(a)) {
  Relation(name: "permutation_of", holds: is_permutation)
}

fn is_permutation(left: List(a), right: List(a)) -> Bool {
  list.length(left) == list.length(right) && remove_each(left, right) == []
}

/// `remaining` with one occurrence of every element of `to_remove`
/// taken out, or a non-empty list as soon as an element is missing.
fn remove_each(to_remove: List(a), remaining: List(a)) -> List(a) {
  case to_remove {
    [] -> remaining
    [first, ..rest] ->
      case remove_one(first, remaining, []) {
        Ok(remaining_after) -> remove_each(rest, remaining_after)
        Error(Nil) -> [first]
      }
  }
}

fn remove_one(target: a, items: List(a), acc: List(a)) -> Result(List(a), Nil) {
  case items {
    [] -> Error(Nil)
    [first, ..rest] if first == target ->
      Ok(list.append(list.reverse(acc), rest))
    [first, ..rest] -> remove_one(target, rest, [first, ..acc])
  }
}
