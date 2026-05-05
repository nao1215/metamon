import gleam/option.{None, Some}
import gleeunit/should
import metamon
import metamon/config

pub fn defaults_are_sane_test() {
  let c = config.default_config()
  should.equal(config.runs(c), 100)
  should.equal(config.max_size(c), 99)
  should.equal(config.shrink_limit(c), 1024)
  should.equal(config.max_edges(c), 16)
  should.equal(config.regression_file(c), None)
  should.equal(config.diff_enabled(c), True)
}

pub fn with_runs_rejects_non_positive_test() {
  let c = config.default_config()
  case config.with_runs(c, 0) {
    Error(config.NonPositive("runs", 0)) -> Nil
    _ -> should.fail()
  }
  case config.with_runs(c, -1) {
    Error(config.NonPositive("runs", -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_runs_accepts_positive_test() {
  let c = config.default_config()
  let assert Ok(c2) = config.with_runs(c, 500)
  should.equal(config.runs(c2), 500)
}

pub fn with_seed_is_total_test() {
  let c = config.default_config()
  let new = config.with_seed(c, metamon.seed(0))
  // should not error (no Result type)
  let _ = new
  Nil
}

pub fn with_regression_file_rejects_empty_test() {
  let c = config.default_config()
  case config.with_regression_file(c, "") {
    Error(config.InvalidPath(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn with_regression_file_accepts_nonempty_test() {
  let c = config.default_config()
  let assert Ok(c2) =
    config.with_regression_file(c, "test/regressions/sample.toml")
  should.equal(config.regression_file(c2), Some("test/regressions/sample.toml"))
}

pub fn with_diff_enabled_toggles_test() {
  let c = config.default_config()
  let off = config.with_diff_enabled(c, False)
  should.equal(config.diff_enabled(off), False)
}
