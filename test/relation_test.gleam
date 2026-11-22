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

pub fn approximately_zero_epsilon_is_exact_equality_test() {
  let r = relation.approximately(0.0)
  // Zero epsilon collapses to exact equality (reflexivity preserved).
  should.be_true(r.holds(1.0, 1.0))
  should.be_false(r.holds(1.0, 1.0000001))
}

pub fn approximately_negative_epsilon_panics_test() {
  // A negative epsilon would silently produce an "always false"
  // relation that breaks reflexivity (`r.holds(x, x) == False` for
  // every x). Reject at construction with a structured panic.
  let outcome =
    capture_panic(fn() {
      let _ = relation.approximately(-1.0)
      Nil
    })
  case outcome {
    PanickedWith(message) -> {
      should.be_true(string.contains(message, "epsilon must be >= 0.0"))
    }
    DidNotPanic -> should.fail()
  }
}

pub type PanicOutcome {
  PanickedWith(message: String)
  DidNotPanic
}

@external(erlang, "metamon_test_ffi", "capture_panic")
@external(javascript, "./metamon_test_ffi.mjs", "capture_panic")
fn capture_panic_raw(thunk: fn() -> Nil) -> #(Bool, String)

fn capture_panic(thunk: fn() -> Nil) -> PanicOutcome {
  let #(panicked, message) = capture_panic_raw(thunk)
  case panicked {
    True -> PanickedWith(message: message)
    False -> DidNotPanic
  }
}

pub fn permutation_of_test() {
  let r = relation.permutation_of()
  should.be_true(r.holds([1, 2, 3], [3, 1, 2]))
  should.be_false(r.holds([1, 2, 3], [1, 2, 4]))
  should.be_false(r.holds([1, 2, 3], [1, 2]))
}
