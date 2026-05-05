//// `metamon.commutativity_of` MR template.
////
//// The template builds an MR over the input pair `#(a, a)` whose
//// transform swaps the two components. Asserting equality of the
//// outputs is exactly the textbook "operation is commutative" check.

import metamon
import metamon/generator
import metamon/generator/range

fn add(a: Int, b: Int) -> Int {
  a + b
}

pub fn integer_addition_is_commutative_test() {
  let mr = metamon.commutativity_of(name: "add_commutative")
  metamon.forall_morph(
    generator.tuple2(
      generator.int(range.constant(-50, 50)),
      generator.int(range.constant(-50, 50)),
    ),
    mr,
    fn(pair) { add(pair.0, pair.1) },
  )
}

fn max_of(a: Int, b: Int) -> Int {
  case a >= b {
    True -> a
    False -> b
  }
}

pub fn integer_max_is_commutative_test() {
  let mr = metamon.commutativity_of(name: "max_commutative")
  metamon.forall_morph(
    generator.tuple2(
      generator.int(range.constant(0, 100)),
      generator.int(range.constant(0, 100)),
    ),
    mr,
    fn(pair) { max_of(pair.0, pair.1) },
  )
}
