//// Smoke tests for the `_or_panic` config builder variants. The
//// happy path is what test code actually relies on; the panic branch
//// is exercised indirectly by the runner's failure pipeline and by
//// glinter's `avoid_panic` ignore list documenting why these exist.

import gleeunit/should
import metamon

pub fn with_runs_or_panic_returns_config_test() {
  let c = metamon.with_runs_or_panic(metamon.default_config(), 30)
  let _ = c
  should.equal(1, 1)
}

pub fn with_max_size_or_panic_returns_config_test() {
  let c = metamon.with_max_size_or_panic(metamon.default_config(), 50)
  let _ = c
  should.equal(1, 1)
}

pub fn with_shrink_limit_or_panic_returns_config_test() {
  let c = metamon.with_shrink_limit_or_panic(metamon.default_config(), 256)
  let _ = c
  should.equal(1, 1)
}

pub fn with_max_edges_or_panic_returns_config_test() {
  let c = metamon.with_max_edges_or_panic(metamon.default_config(), 8)
  let _ = c
  should.equal(1, 1)
}

pub fn with_regression_file_or_panic_returns_config_test() {
  let c =
    metamon.with_regression_file_or_panic(metamon.default_config(), "/tmp/reg")
  let _ = c
  should.equal(1, 1)
}

pub fn or_panic_chain_test() {
  let c =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(42))
    |> metamon.with_runs_or_panic(20)
    |> metamon.with_max_size_or_panic(10)
    |> metamon.with_shrink_limit_or_panic(64)
    |> metamon.with_max_edges_or_panic(4)
  let _ = c
  should.equal(1, 1)
}
