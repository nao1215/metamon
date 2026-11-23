# metamon

[![CI](https://github.com/nao1215/metamon/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/metamon/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/metamon/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/metamon/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/metamon/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/metamon)](https://hex.pm/packages/metamon)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/metamon/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/metamon)](https://hex.pm/packages/metamon)
[![License](https://img.shields.io/github/license/nao1215/metamon)](https://github.com/nao1215/metamon/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/metamon/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/metamon)


Property-based and metamorphic testing for Gleam, on Erlang and JavaScript. A property checks one input; a metamorphic relation checks how the outputs for two related inputs, such as `f(x)` and `f(list.reverse(x))`, must relate. metamon generates inputs, shrinks a failing one and prints a report with the seed that reproduces it.

```sh
gleam add --dev metamon@0
```

## Properties

A property is a function that panics when it does not hold, so Gleam's `assert` works inside it.

```gleam
import gleam/list
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
```

When a property fails, metamon shrinks the input and panics with a report. For `assert list.reverse(items) == items` the report starts like this:

```text
× property failed
  test:        forall
  source:      edge(2)
  config seed: 42
  runs:        2 / 100
  shrinks:     2

  source input  (shrunk):
    [0, 1]

  panic message:
    Assertion failed.
```

## Metamorphic relations

`forall_morph` runs a function on an input and on transformed inputs, and checks each pair of outputs with a relation. It helps when the right output is hard to state but how it must change is easy to state.

```gleam
import gleam/int
import gleam/list
import metamon
import metamon/generator

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
```

`Equivariant` relates a transform of the input to a transform of the output, and `equivalent_under`, `approximately` and `permutation_of` compare outputs by something other than `==`. `forall_round_trip` checks that `decode(encode(x)) == Ok(x)`:

```gleam
import gleam/bit_array
import metamon
import metamon/generator

pub fn base64_test() {
  metamon.forall_round_trip(
    generator: generator.bit_array(bytes: generator.range(from: 0, to: 64)),
    name: "base64",
    encode: bit_array.base64_encode(_, True),
    decode: bit_array.base64_decode,
  )
}
```

## Configuration and coverage

`Config` is a plain record. Override fields of `default_config()` and pass it to the `_with` runners. A fixed `seed` makes a run reproducible; `regression_file` records failing inputs and replays them on later runs.

```gleam
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator

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
```

`classify` counts inputs by label, `cover` fails the run when a label is hit less often than the given percentage, and `annotate` adds a labelled value to the failure report.

Further documentation can be found at <https://hexdocs.pm/metamon>.

## Verifying releases

Each GitHub Release attaches the tarball published to Hex (`metamon-<version>.tar`), `checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and build provenance (`metamon-<version>.intoto.jsonl`). The release workflow downloads the tarball from Hex after `gleam publish` and checks it against the checksum Hex records before signing it, so the tarball you get from Hex is the one that is signed and attested.

```sh
curl -fsSLO https://repo.hex.pm/tarballs/metamon-<version>.tar
gh attestation verify metamon-<version>.tar --repo nao1215/metamon
```

To check the signature as well, download `checksums.txt` and `checksums.txt.sigstore.json` from the Release into the same directory. The workflow runs on the release tag, or on `main` when the assets of a published tag are attached again.

```sh
cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/metamon/\.github/workflows/release\.yml@refs/(tags/v.+|heads/main)$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/metamon/blob/main/LICENSE)
