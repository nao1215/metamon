//// `Config.max_size` reaches the generators: a linear range spans its
//// full width at size = max_size, whatever max_size is.

import gleam/list
import gleam/option.{Some}
import metamon
import metamon/generator
import test_helpers

fn config(max_size: Int, runs: Int) -> metamon.Config {
  metamon.Config(
    ..metamon.default_config(),
    seed: Some(11),
    runs: runs,
    max_size: max_size,
  )
}

pub fn small_max_size_still_reaches_the_full_range_test() {
  let #(panicked, _) =
    test_helpers.capture_panic(fn() {
      metamon.forall_with(
        config(10, 1000),
        generator.int(generator.linear_range(0, 1000)) |> generator.no_edges,
        fn(x) {
          assert x < 200
        },
      )
    })
  assert panicked
}

pub fn linear_bounds_scale_with_the_configured_max_size_test() {
  let sized_value =
    generator.sized(fn(size) {
      generator.int(generator.linear_range(0, 1_000_000))
      |> generator.map(fn(x) { #(size, x) })
    })
    |> generator.no_edges
  list.each([1, 7, 10, 50, 99, 100, 500, 1000], fn(max_size) {
    metamon.forall_with(config(max_size, 100), sized_value, fn(pair) {
      let #(size, x) = pair
      assert size <= max_size && x <= 1_000_000 * size / max_size
    })
  })
}

pub fn list_length_scales_with_the_configured_max_size_test() {
  let sized_list =
    generator.sized(fn(size) {
      generator.list_of(generator.return(0), generator.linear_range(0, 1000))
      |> generator.map(fn(items) { #(size, list.length(items)) })
    })
    |> generator.no_edges
  metamon.forall_with(config(1000, 100), sized_list, fn(pair) {
    assert pair.1 <= pair.0
  })
}
