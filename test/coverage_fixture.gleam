//// Measured by `the_measuring_erl_counts_each_branch_test` in
//// mutation_test.gleam, which checks the line numbers of `sign`.

pub fn sign(number: Int) -> String {
  case number < 0 {
    True -> "negative"
    False -> "not negative"
  }
}

pub fn sign_test() {
  assert sign(1) == "not negative"
}
