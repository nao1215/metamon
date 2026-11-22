//// Annotations appear in the failure report in the order they were
//// added, and only the failing run's annotations are shown.

import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/annotate
import metamon/generator
import metamon/generator/range
import test_helpers

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
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
        test_helpers.fail()
      })
    })
  assert string.contains(text, annotations_block(labels) <> "\n\n")
}

pub fn annotations_keep_order_for_any_count_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 30),
    generator.int(range.constant(1, 40)),
    fn(count) {
      let labels = list.map(test_helpers.integers_from(0, count), int.to_string)
      let text =
        failure_text(fn() {
          metamon.forall(generator.return(0), fn(_) {
            list.each(labels, annotate.annotate)
            test_helpers.fail()
          })
        })
      assert string.contains(text, annotations_block(labels) <> "\n\n")
    },
  )
}

pub fn passing_runs_do_not_leak_annotations_test() {
  let cfg = metamon.Config(..metamon.default_config(), seed: Some(5), runs: 200)
  let text =
    failure_text(fn() {
      metamon.forall_with(
        cfg,
        generator.int(range.linear(0, 1000)) |> generator.no_edges,
        fn(x) {
          annotate.annotate_value("x", x)
          assert x < 500
        },
      )
    })
  assert list.length(string.split(text, "    - x: ")) == 2
}
