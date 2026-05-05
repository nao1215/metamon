import gleam/list
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
import metamon/transform/list as list_t
import metamon/transform/string as string_t

// A function that is genuinely idempotent: trim removes leading/
// trailing spaces, applying twice == applying once.
fn trim_idempotent_test_input() -> Nil {
  let mr = metamon.idempotency_of(string.trim, "string.trim_idempotent")
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 8)),
    mr,
    string.trim,
  )
}

pub fn idempotency_template_passes_for_trim_test() {
  trim_idempotent_test_input()
}

// `list.length` is invariant under reverse → invariant_under MR
// expects `f(reverse(xs)) == f(xs)`.
pub fn invariant_under_reverse_for_length_test() {
  let mr =
    metamon.invariant_under(list_t.reverse(), "length_invariant_under_reverse")
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    mr,
    list.length,
  )
}

// Equivariant: `list.map(f)(reverse(xs)) == reverse(list.map(f)(xs))`.
pub fn equivariant_map_under_reverse_test() {
  let plus_one = fn(n) { n + 1 }
  let mr =
    metamon.equivariant_under(
      list_t.reverse(),
      list_t.reverse(),
      relation.equal(),
      "map_commutes_with_reverse",
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    mr,
    fn(items) { list.map(items, plus_one) },
  )
}

// Plain MR built manually: `string.uppercase` is invariant under
// `string.lowercase` ∘ `string.uppercase` (idempotency-flavoured).
pub fn manual_plain_mr_test() {
  let upper_then_lower =
    transform.then(string_t.uppercase(), string_t.lowercase())
  let mr =
    metamon.mr(
      name: "uppercase_after_normalisation",
      transform: upper_then_lower,
      relation: relation.equal(),
    )
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 6)),
    mr,
    string.uppercase,
  )
}

// assert_morph runs against a single hand-supplied input.
pub fn assert_morph_succeeds_test() {
  let mr =
    metamon.invariant_under(list_t.reverse(), "sum_invariant_under_reverse")
  metamon.assert_morph([1, 2, 3, 4], mr, list_sum)
}

fn list_sum(items: List(Int)) -> Int {
  list.fold(items, 0, fn(acc, n) { acc + n })
}

// forall_morphs runs several MRs in sequence. We use two MRs that
// are both true for the same function (sum).
pub fn forall_morphs_runs_each_mr_test() {
  let invariant = metamon.invariant_under(list_t.reverse(), "sum_reverse")
  let plus_zero =
    metamon.invariant_under(list_t.append(0), "sum_append_zero_no_op")
  metamon.forall_morphs(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 4)),
    [invariant, plus_zero],
    list_sum,
  )
  should.equal(1, 1)
}

pub fn name_of_returns_constructed_name_test() {
  let mr = metamon.invariant_under(list_t.reverse(), "the_name")
  should.equal(metamon.name_of(mr), "the_name")
}
