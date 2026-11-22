//// The examples in README.md, kept here so they keep compiling and keep
//// passing.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator

pub fn reverse_twice_test() {
  let lists =
    generator.list_of(
      generator.int(generator.range(from: -100, to: 100)),
      length: generator.range(from: 0, to: 20),
    )
  metamon.forall(lists, fn(items) {
    assert list.reverse(list.reverse(items)) == items
  })
}

pub fn sum_test() {
  let lists =
    generator.list_of(
      generator.int(generator.range(from: -100, to: 100)),
      length: generator.range(from: 0, to: 20),
    )
  let reverse = metamon.Transform(name: "list.reverse", apply: list.reverse)
  let append_zero =
    metamon.Transform(name: "append 0", apply: fn(items) {
      list.append(items, [0])
    })
  metamon.forall_morph(
    lists,
    [
      metamon.invariant_under(name: "order does not matter", under: reverse),
      metamon.Morph(
        name: "adding 0 changes nothing",
        transform: append_zero,
        relation: metamon.equal(),
      ),
    ],
    int.sum,
  )
}

pub fn sort_test() {
  let lists =
    generator.list_of(
      generator.int(generator.range(from: -100, to: 100)),
      length: generator.range(from: 0, to: 20),
    )
  let sort = list.sort(_, int.compare)
  metamon.forall_morph(
    lists,
    [metamon.idempotency_of(name: "sort", of: sort)],
    sort,
  )
}

pub fn base64_test() {
  metamon.forall_round_trip(
    generator: generator.bit_array(bytes: generator.range(from: 0, to: 64)),
    name: "base64",
    encode: bit_array.base64_encode(_, True),
    decode: bit_array.base64_decode,
  )
}

pub fn trim_test() {
  let config =
    metamon.Config(..metamon.default_config(), runs: 300, seed: Some(42))
  let words =
    generator.string(
      of: generator.Alphanumeric,
      length: generator.range(from: 0, to: 8),
    )
  metamon.forall_with(config, words, fn(word) {
    metamon.classify(label: "empty", when: word == "")
    metamon.cover(at_least: 50.0, label: "non-empty", when: word != "")
    assert string.trim(word) == word
  })
}
