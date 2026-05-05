//// `metamon.forall_morph_n`: N-ary metamorphic relation across many
//// follow-up inputs in a single check.

import gleam/list
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform/list as list_t

fn list_sum(items: List(Int)) -> Int {
  list.fold(items, 0, fn(acc, n) { acc + n })
}

pub fn sum_under_three_invariants_test() {
  // sum is invariant under reverse, dedupe (since input has no
  // duplicates with this generator, dedupe is identity), and
  // appending zero. Asserting all four outputs are equal in one
  // shot is exactly what `forall_morph_n + all_equal()` does.
  metamon.forall_morph_n(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 4)),
    [list_t.reverse(), list_t.append(0)],
    relation.all_equal(),
    list_sum,
  )
}

pub fn list_length_pairwise_equal_under_reverse_chain_test() {
  // length is preserved by any number of reverses; pairwise equality
  // catches the degenerate "first == last but middle differs" case.
  metamon.forall_morph_n(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    [list_t.reverse(), list_t.reverse(), list_t.reverse()],
    relation.pairwise(relation.equal()),
    list.length,
  )
}
