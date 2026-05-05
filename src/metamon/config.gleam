//// Configuration for property and metamorphic runs. Construct via
//// `default_config()` and the `with_*` builders. All builders that
//// validate input return a `Result` so misconfiguration is visible
//// at the type level (no silent fallback).

import gleam/option.{type Option, None, Some}
import metamon/generator/seed.{type Seed} as seed_module

/// Errors returned by `with_*` builders for invalid inputs.
pub type ConfigError {
  /// A field that must be positive received a non-positive value.
  NonPositive(field: String, value: Int)
  /// A path field received an empty or otherwise invalid string.
  InvalidPath(path: String, reason: String)
}

/// Failure-report output format.
pub type OutputFormat {
  /// Multi-line human-readable text (the default).
  Text
  /// Single-line JSON object suitable for CI annotations and LLM parsing.
  Json
}

/// Opaque configuration record. Use `default_config()` and `with_*`
/// to build instances.
pub opaque type Config {
  Config(
    runs: Int,
    seed: Seed,
    max_size: Int,
    shrink_limit: Int,
    max_edges: Int,
    regression_file: Option(String),
    diff_enabled: Bool,
    output_format: OutputFormat,
  )
}

/// Default configuration: 100 runs, max_size 99, random seed, etc.
pub fn default_config() -> Config {
  Config(
    runs: 100,
    seed: seed_module.random_seed(),
    max_size: 99,
    shrink_limit: 1024,
    max_edges: 16,
    regression_file: None,
    diff_enabled: True,
    output_format: Text,
  )
}

/// Override the number of successful runs.
pub fn with_runs(c: Config, n: Int) -> Result(Config, ConfigError) {
  case n <= 0 {
    True -> Error(NonPositive(field: "runs", value: n))
    False -> Ok(Config(..c, runs: n))
  }
}

/// Override the seed.
pub fn with_seed(c: Config, s: Seed) -> Config {
  Config(..c, seed: s)
}

/// Override `max_size`.
pub fn with_max_size(c: Config, n: Int) -> Result(Config, ConfigError) {
  case n <= 0 {
    True -> Error(NonPositive(field: "max_size", value: n))
    False -> Ok(Config(..c, max_size: n))
  }
}

/// Override the shrink limit.
pub fn with_shrink_limit(c: Config, n: Int) -> Result(Config, ConfigError) {
  case n <= 0 {
    True -> Error(NonPositive(field: "shrink_limit", value: n))
    False -> Ok(Config(..c, shrink_limit: n))
  }
}

/// Override the cap on the size of edge cartesian products.
pub fn with_max_edges(c: Config, n: Int) -> Result(Config, ConfigError) {
  case n <= 0 {
    True -> Error(NonPositive(field: "max_edges", value: n))
    False -> Ok(Config(..c, max_edges: n))
  }
}

/// Set a regression file path. The file is created on first failure
/// and read on every subsequent run.
pub fn with_regression_file(
  c: Config,
  path: String,
) -> Result(Config, ConfigError) {
  case path {
    "" -> Error(InvalidPath(path: path, reason: "empty"))
    _ -> Ok(Config(..c, regression_file: Some(path)))
  }
}

/// Enable or disable structural diff in failure output.
pub fn with_diff_enabled(c: Config, enabled: Bool) -> Config {
  Config(..c, diff_enabled: enabled)
}

/// Choose the failure-report output format. `Text` is the default;
/// `Json` produces a single-line JSON object suitable for piping
/// into CI dashboards or LLM-driven analysis.
pub fn with_output_format(c: Config, fmt: OutputFormat) -> Config {
  Config(..c, output_format: fmt)
}

// ---------- read-only accessors ----------

/// The number of successful runs the runner targets per property.
pub fn runs(c: Config) -> Int {
  c.runs
}

/// The seed used to drive the deterministic PRNG. `with_seed`
/// pins this to a fixed value for reproducibility.
pub fn seed(c: Config) -> Seed {
  c.seed
}

/// Upper bound on the `Range` size parameter; controls the
/// complexity ramp from the first run to the last.
pub fn max_size(c: Config) -> Int {
  c.max_size
}

/// Maximum number of shrink steps the runner attempts on a single
/// failure before giving up.
pub fn shrink_limit(c: Config) -> Int {
  c.shrink_limit
}

/// Cap on the size of the cartesian-product edge sets that
/// combinators like `tuple2` / `map2` build up.
pub fn max_edges(c: Config) -> Int {
  c.max_edges
}

/// Path to the regression file; `None` disables the feature.
pub fn regression_file(c: Config) -> Option(String) {
  c.regression_file
}

/// Whether structural diff is shown in failure output.
pub fn diff_enabled(c: Config) -> Bool {
  c.diff_enabled
}

/// Selected failure-report format (`Text` or `Json`).
pub fn output_format(c: Config) -> OutputFormat {
  c.output_format
}
