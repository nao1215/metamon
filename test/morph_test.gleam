import gleam/list
import gleam/string
import gleeunit/should
import metamon
import metamon/generator
import metamon/generator/range
import test_helpers

// A function that is genuinely idempotent: trim removes leading/
// trailing spaces, applying twice == applying once.
fn trim_idempotent_test_input() -> Nil {
  let mr =
    metamon.idempotency_of(name: "string.trim_idempotent", of: string.trim)
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 8)),
    [mr],
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
    metamon.invariant_under(
      name: "length_invariant_under_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    [mr],
    list.length,
  )
}

// Equivariant: `list.map(f)(reverse(xs)) == reverse(list.map(f)(xs))`.
pub fn equivariant_map_under_reverse_test() {
  let plus_one = fn(n) { n + 1 }
  let mr =
    metamon.Equivariant(
      name: "map_commutes_with_reverse",
      input: metamon.Transform("list.reverse", list.reverse),
      output: metamon.Transform("list.reverse", list.reverse),
      relation: metamon.equal(),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 5)),
    [mr],
    fn(items) { list.map(items, plus_one) },
  )
}

// Plain MR built manually: `string.uppercase` is invariant under
// `string.lowercase` ∘ `string.uppercase` (idempotency-flavoured).
pub fn manual_plain_mr_test() {
  let upper_then_lower =
    metamon.Transform("string.uppercase |> string.lowercase", fn(text) {
      string.lowercase(string.uppercase(text))
    })
  let mr =
    metamon.Morph(
      name: "uppercase_after_normalisation",
      transform: upper_then_lower,
      relation: metamon.equal(),
    )
  metamon.forall_morph(
    generator.string_ascii(range.constant(0, 6)),
    [mr],
    string.uppercase,
  )
}

// assert_morph runs against a single hand-supplied input.
pub fn assert_morph_succeeds_test() {
  let mr =
    metamon.invariant_under(
      name: "sum_invariant_under_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  metamon.assert_morph([1, 2, 3, 4], mr, list_sum)
}

fn list_sum(items: List(Int)) -> Int {
  list.fold(items, 0, fn(acc, n) { acc + n })
}

// forall_morph runs several morphs in sequence. We use two morphs that
// are both true for the same function (sum).
pub fn forall_morph_runs_each_morph_test() {
  let invariant =
    metamon.invariant_under(
      name: "sum_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  let plus_zero =
    metamon.invariant_under(
      name: "sum_append_zero_no_op",
      under: metamon.Transform("list.append(0)", fn(items) {
        list.append(items, [0])
      }),
    )
  metamon.forall_morph(
    generator.list_of(generator.int(range.constant(0, 9)), range.constant(0, 4)),
    [invariant, plus_zero],
    list_sum,
  )
}

pub fn morph_name_is_a_field_test() {
  let mr =
    metamon.invariant_under(
      name: "the_name",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  should.equal(mr.name, "the_name")
}

pub fn forall_morph_reports_every_failing_morph_test() {
  let not_head =
    metamon.invariant_under(
      name: "head_under_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  let not_head_after_append =
    metamon.invariant_under(
      name: "head_under_prepend",
      under: metamon.Transform("list.prepend(9)", fn(items) { [9, ..items] }),
    )
  let holds =
    metamon.invariant_under(
      name: "head_under_identity",
      under: metamon.Transform("identity", fn(items) { items }),
    )
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_morph(
        generator.list_of(
          generator.int(range.constant(0, 5)),
          range.constant(2, 4),
        ),
        [not_head, holds, not_head_after_append],
        list.first,
      )
    })
  assert panicked
  assert string.contains(text, "one or more metamorphic relations failed")
  assert string.contains(text, "`head_under_reverse` failed")
  assert string.contains(text, "`head_under_prepend` failed")
  assert !string.contains(text, "`head_under_identity` failed")
}

pub fn forall_morph_with_one_failure_shows_only_its_report_test() {
  let not_head =
    metamon.invariant_under(
      name: "head_under_reverse",
      under: metamon.Transform("list.reverse", list.reverse),
    )
  let #(panicked, text) =
    test_helpers.capture_panic(fn() {
      metamon.forall_morph(
        generator.list_of(
          generator.int(range.constant(0, 5)),
          range.constant(2, 4),
        ),
        [not_head],
        list.first,
      )
    })
  assert panicked
  assert string.starts_with(
    text,
    "× metamorphic relation `head_under_reverse` failed",
  )
}
