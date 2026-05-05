import gleam/order
import gleam/string
import gleeunit/should
import metamon/relation

pub fn equal_holds_when_structurally_same_test() {
  let r_int = relation.equal()
  should.be_true(r_int.holds(1, 1))
  should.be_false(r_int.holds(1, 2))
  let r_list = relation.equal()
  should.be_true(r_list.holds([1, 2, 3], [1, 2, 3]))
}

pub fn not_equal_inverts_equal_test() {
  let r = relation.not_equal()
  should.be_false(r.holds(1, 1))
  should.be_true(r.holds(1, 2))
}

pub fn equivalent_under_normalises_first_test() {
  // "a/b/c" and "a//b/c" are equal modulo collapsing repeated slashes.
  let r = relation.equivalent_under(collapse_slashes, "collapse_slashes")
  should.be_true(r.holds("a/b/c", "a//b/c"))
  should.be_false(r.holds("a/b/c", "a/b/d"))
}

fn collapse_slashes(s: String) -> String {
  case string.contains(s, "//") {
    True -> collapse_slashes(string.replace(s, "//", "/"))
    False -> s
  }
}

pub fn approximately_within_epsilon_test() {
  let r = relation.approximately(0.1)
  should.be_true(r.holds(1.0, 1.05))
  should.be_false(r.holds(1.0, 2.0))
}

pub fn permutation_of_test() {
  let r = relation.permutation_of()
  should.be_true(r.holds([1, 2, 3], [3, 1, 2]))
  should.be_false(r.holds([1, 2, 3], [1, 2, 4]))
  should.be_false(r.holds([1, 2, 3], [1, 2]))
}

pub fn subset_of_test() {
  let r = relation.subset_of()
  should.be_true(r.holds([1, 2], [1, 2, 3]))
  should.be_false(r.holds([1, 2, 4], [1, 2, 3]))
}

pub fn monotone_test() {
  let r =
    relation.monotone(fn(a, b) {
      case a == b, a < b {
        True, _ -> order.Eq
        _, True -> order.Lt
        _, _ -> order.Gt
      }
    })
  should.be_true(r.holds(1, 2))
  should.be_true(r.holds(1, 1))
  should.be_false(r.holds(2, 1))
}

pub fn implies_short_circuits_when_antecedent_false_test() {
  let inner = relation.equal()
  let r = relation.implies(fn(a, b) { a > 0 && b > 0 }, inner)
  // Antecedent false → trivially holds even if values differ.
  should.be_true(r.holds(-1, 5))
  // Antecedent true → inner equality must hold.
  should.be_false(r.holds(1, 2))
  should.be_true(r.holds(1, 1))
}

pub fn and_or_invert_test() {
  let one_or_two = relation.new("one_or_two", fn(a, _b) { a == 1 || a == 2 })
  let positive = relation.new("positive", fn(a, _b) { a > 0 })
  let both = relation.and(one_or_two, positive)
  should.be_true(both.holds(1, 0))
  should.be_false(both.holds(-1, 0))
  let either = relation.or(one_or_two, positive)
  should.be_true(either.holds(5, 0))
  // Invert
  let neither = relation.invert(either)
  should.be_true(neither.holds(-1, 0))
}

pub fn rename_keeps_predicate_test() {
  let r =
    relation.equal()
    |> relation.rename("structural_eq")
  should.equal(r.name, "structural_eq")
  should.be_true(r.holds(1, 1))
}
