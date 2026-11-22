//// The plain property runners (`forall`, `forall_with`,
//// `forall_round_trip*`) shrink the failing input the same way
//// `forall_morph` does.

import gleam/int
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic(thunk: fn() -> Nil) -> #(Bool, String)

fn failure_text(thunk: fn() -> Nil) -> String {
  let #(panicked, message) = capture_panic(thunk)
  assert panicked
  message
}

fn seeded(value: Int) -> metamon.Config {
  metamon.default_config() |> metamon.with_seed(metamon.seed(value))
}

fn ints() -> generator.Generator(Int) {
  generator.int(range.constant(0, 1000)) |> generator.no_edges
}

fn shrunk_to(text: String, rendered: String) -> Bool {
  string.contains(text, "source input  (shrunk):\n    " <> rendered <> "\n")
}

pub fn forall_with_shrinks_to_the_smallest_counterexample_test() {
  let text =
    failure_text(fn() {
      metamon.forall_with(seeded(42), ints(), fn(x) { x < 10 })
    })
  assert shrunk_to(text, "10")
  assert !string.contains(text, "shrinks:     0\n")
}

pub fn forall_shrinks_to_the_boundary_for_every_seed_test() {
  // Metamorphic over the seed: whichever failing input the run hits
  // first, the reported input is the boundary value.
  metamon.forall_with(
    metamon.default_config() |> metamon.with_runs_or_panic(20),
    generator.int(range.constant(1, 100_000)),
    fn(seed_value) {
      let text =
        failure_text(fn() {
          metamon.forall_with(seeded(seed_value), ints(), fn(x) { x < 10 })
        })
      shrunk_to(text, "10")
    },
  )
}

pub fn forall_round_trip_shrinks_test() {
  let text =
    failure_text(fn() {
      metamon.forall_round_trip_with(
        cfg: seeded(3),
        gen: ints(),
        name: "lossy",
        encode: int.to_string,
        decode: fn(s) {
          case int.parse(s) {
            Ok(n) if n >= 10 -> Ok(n + 1)
            other -> other
          }
        },
      )
    })
  assert shrunk_to(text, "10")
}
