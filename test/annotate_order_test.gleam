//// Annotations appear in the failure report in the order they were
//// added, and only the failing run's annotations are shown.

import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/annotate
import metamon/generator
import metamon/generator/range
import test_helpers

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = capture_panic(thunk)
  assert panicked
  message
}

fn annotations_block(labels: List(String)) -> String {
  "  annotations:\n"
  <> string.join(list.map(labels, fn(label) { "    - " <> label }), "\n")
}

pub fn annotations_keep_registration_order_test() {
  let labels = ["first", "second", "third", "fourth"]
  let text =
    failure_text(fn() {
      metamon.forall(generator.return(0), fn(_) {
        list.each(labels, annotate.annotate)
        False
      })
    })
  assert string.contains(text, annotations_block(labels) <> "\n\n")
}

pub fn annotations_keep_order_for_any_count_test() {
  metamon.forall_with(
    metamon.default_config() |> metamon.with_runs_or_panic(30),
    generator.int(range.constant(1, 40)),
    fn(count) {
      let labels = list.map(test_helpers.integers_from(0, count), int.to_string)
      let text =
        failure_text(fn() {
          metamon.forall(generator.return(0), fn(_) {
            list.each(labels, annotate.annotate)
            False
          })
        })
      string.contains(text, annotations_block(labels) <> "\n\n")
    },
  )
}

pub fn passing_runs_do_not_leak_annotations_test() {
  let cfg =
    metamon.default_config()
    |> metamon.with_seed(metamon.seed(5))
    |> metamon.with_runs_or_panic(200)
  let text =
    failure_text(fn() {
      metamon.forall_with(
        cfg,
        generator.int(range.linear(0, 1000)) |> generator.no_edges,
        fn(x) {
          annotate.annotate_value("x", x)
          x < 500
        },
      )
    })
  assert list.length(string.split(text, "    - x: ")) == 2
}
