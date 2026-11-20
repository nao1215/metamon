# Case study: CRDT algebraic laws

A CRDT's `merge` must satisfy three laws:

| Law | Statement |
|-----|-----------|
| Idempotency | `merge(a, a) == a` |
| Commutativity | `merge(a, b) == merge(b, a)` |
| Associativity | `merge(merge(a, b), c) == merge(a, merge(b, c))` |

A G-Counter holds a counter per node, and `merge` takes the per-key max:

```gleam
import gleam/dict.{type Dict}
import gleam/list
import metamon
import metamon/generator
import metamon/generator/range

type GCounter =
  Dict(String, Int)

fn merge(left: GCounter, right: GCounter) -> GCounter {
  dict.fold(right, left, fn(acc, key, value) {
    case dict.get(acc, key) {
      Ok(current) if current >= value -> acc
      _ -> dict.insert(acc, key, value)
    }
  })
}

fn make_gcounter(pairs: List(#(String, Int))) -> GCounter {
  list.fold(pairs, dict.new(), fn(acc, pair) {
    dict.insert(acc, pair.0, pair.1)
  })
}

pub fn readme_gcounter_idempotent_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(seed) {
    let counter =
      make_gcounter([
        #("node-A", seed),
        #("node-B", seed * 2),
        #("node-C", seed * 3),
      ])
    merge(counter, counter) == counter
  })
}

pub fn readme_gcounter_commutative_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(seed) {
    let left = make_gcounter([#("node-A", seed), #("node-B", seed * 2)])
    let right = make_gcounter([#("node-A", seed + 1), #("node-C", seed * 3)])
    merge(left, right) == merge(right, left)
  })
}

pub fn readme_gcounter_associative_test() {
  metamon.forall(generator.int(range.constant(0, 100)), fn(seed) {
    let a = make_gcounter([#("X", seed), #("Y", seed + 1)])
    let b = make_gcounter([#("X", seed + 5), #("Z", seed + 7)])
    let c = make_gcounter([#("Y", seed + 9), #("Z", seed + 11)])
    merge(merge(a, b), c) == merge(a, merge(b, c))
  })
}
```

`idempotency_of` and `commutativity_of` are templates over a unary `f: a -> a`, so laws on a binary or ternary `merge` use `forall`. The generator produces an `Int` seed and the test derives the counters from it. If associativity fails, replicas that received the same operations in a different order diverge.

The three tests are mirrored in `test/readme_test.gleam`.
