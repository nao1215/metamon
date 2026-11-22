// Test-only FFI: run a thunk and report whether it panicked.

export function capture_panic(thunk) {
  // Mirror of `metamon_test_ffi:capture_panic/1`: runs `thunk` and reports
  // `(panicked, message)` to the caller. Used by tests that exercise
  // the failure path of `metamon.forall` without aborting the test
  // process.
  try {
    thunk();
    return [false, ""];
  } catch (error) {
    let message;
    if (error && typeof error === "object" && error.message) {
      message = error.message;
    } else {
      message = String(error);
    }
    return [true, message];
  }
}
