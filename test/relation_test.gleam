import gleam/string
import gleeunit/should
import metamon
import metamon/internal/float_special
import test_helpers

pub fn equal_holds_when_structurally_same_test() {
  let r_int = metamon.equal()
  should.be_true(r_int.holds(1, 1))
  should.be_false(r_int.holds(1, 2))
  let r_list = metamon.equal()
  should.be_true(r_list.holds([1, 2, 3], [1, 2, 3]))
}

pub fn equivalent_under_normalises_first_test() {
  // "a/b/c" and "a//b/c" are equal modulo collapsing repeated slashes.
  let r =
    metamon.equivalent_under(name: "collapse_slashes", via: collapse_slashes)
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
  let r = metamon.approximately(0.1)
  should.be_true(r.holds(1.0, 1.05))
  should.be_false(r.holds(1.0, 2.0))
}

pub fn approximately_zero_epsilon_is_exact_equality_test() {
  let r = metamon.approximately(0.0)
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
      let _ = metamon.approximately(-1.0)
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

fn capture_panic(thunk: fn() -> Nil) -> PanicOutcome {
  let #(panicked, message) = test_helpers.capture_panic(thunk)
  case panicked {
    True -> PanickedWith(message: message)
    False -> DidNotPanic
  }
}

pub fn permutation_of_test() {
  let r = metamon.permutation_of()
  should.be_true(r.holds([1, 2, 3], [3, 1, 2]))
  should.be_false(r.holds([1, 2, 3], [1, 2, 4]))
  should.be_false(r.holds([1, 2, 3], [1, 2]))
}

pub fn approximately_rejects_nan_test() {
  // Erlang cannot build NaN, so float_special.nan() is a finite stand-in
  // there and only the JavaScript target exercises the NaN branch.
  let nan = float_special.nan()
  let #(panicked, message) =
    test_helpers.capture_panic(fn() { metamon.approximately(within: nan) })
  // NaN is neither >= 0.0 nor < 0.0.
  case nan >=. 0.0 || nan <. 0.0 {
    True -> should.be_false(panicked)
    False -> {
      should.be_true(panicked)
      should.be_true(string.contains(message, "metamon.approximately"))
    }
  }
}
