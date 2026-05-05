//// Smoke tests for the shortcut generators added on top of the
//// range-based primitives. They ensure the generated values respect
//// the documented bounds.

import gleam/bit_array
import gleam/list
import gleeunit/should
import metamon/generator
import metamon/generator/range
import metamon/generator/seed

pub fn bool_yields_both_values_test() {
  let g = generator.bool()
  let observed =
    list.map([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
      generator.generate(g, seed.seed(i), 50).value
    })
  should.be_true(list.contains(observed, True))
  should.be_true(list.contains(observed, False))
}

pub fn non_negative_int_is_non_negative_test() {
  let g = generator.non_negative_int()
  list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
    let n = generator.generate(g, seed.seed(i), 99).value
    should.be_true(n >= 0)
  })
}

pub fn positive_int_is_strictly_positive_test() {
  let g = generator.positive_int()
  list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
    let n = generator.generate(g, seed.seed(i), 99).value
    should.be_true(n >= 1)
  })
}

pub fn negative_int_is_strictly_negative_test() {
  let g = generator.negative_int()
  list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
    let n = generator.generate(g, seed.seed(i), 99).value
    should.be_true(n <= -1)
  })
}

pub fn byte_in_unsigned_byte_range_test() {
  let g = generator.byte()
  list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
    let n = generator.generate(g, seed.seed(i), 99).value
    should.be_true(n >= 0 && n <= 255)
  })
}

pub fn bit_array_byte_length_in_bounds_test() {
  let g = generator.bit_array(range.constant(0, 4))
  list.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], fn(i) {
    let bits = generator.generate(g, seed.seed(i), 99).value
    let byte_size = bit_array.byte_size(bits)
    should.be_true(byte_size >= 0 && byte_size <= 4)
  })
}
