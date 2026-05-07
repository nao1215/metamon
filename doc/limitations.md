# Limitations

These are deliberate scope cuts, not bugs. They are listed so you
know what failure or surprise to expect and how to work around it.

## `Transform(a)` is `a -> a`

Type-changing transformations (`String -> Result(Spec, Error)`) cannot
live inside the input transform of an MR.

Workaround: encode the type change as `f` itself and use the output
side of an Equivariant MR (or a plain `forall`) to assert the
relation.

## `Relation(b)` compares two `b` values

Heterogeneous relations `(a, b) -> Bool` (e.g. "the output is bounded
by the input") are not directly expressible.

Workaround: use `metamon.forall` with a hand-written predicate that
closes over both values.

## `bind` shrinks shallowly

Generators built with `bind` keep the outer shrink tree but the inner
shrinks reflect only the first inner generator metamon saw — the
shrunk failure may show an inner value that is not minimal.

Workaround: prefer applicative composition (`map2` … `map8`,
`tuple2` … `tuple8`) over monadic chains when both shapes fit. Reach
for `bind` only when the inner shape genuinely depends on the outer
value.

## `recursive` does not swap branches during shrinking

A failing `Node(left, right)` does not automatically reduce to either
`left` or `right`; only the contained leaves shrink toward their
origins.

Workaround: add `with_examples` listing the small base shapes
(`Leaf(0)`, `Node(Leaf(0), Leaf(0))`, etc.) so the runner tries them
explicitly before random sampling.

## `generator.filter` panics after 100 consecutive rejections

The `filter_retry_limit` is hard-coded; predicates that accept less
than ~1% of generated values will hit the panic with the message
`metamon.filter: predicate rejected the configured number of
candidates in a row; the predicate is too strict`.

Workaround: tighten the underlying generator instead of filtering
downstream — e.g. `int(range.constant(0, 9))` rather than
`int(range.constant(-100, 100)) |> filter(fn(n) { n >= 0 && n <= 9 })`.

## `with_examples` accumulates and does not deduplicate

Calling it twice with overlapping lists yields duplicate edges; the
runner will try each duplicate separately before falling through to
random sampling.

Workaround: dedupe the example list yourself before passing it in, or
use `add_edges` with a single known-unique set. The accumulation
behaviour is intentional — composing a child generator's edges with
its parent's needs append, not merge.

## JavaScript-target parallel runners

`metamon/annotate` and `metamon/coverage` use a module-level `Map` on
the JS target. Vitest / Jest workers run each test file in an isolated
worker thread, so parallelism between files is fine.

Workaround: within a single file, do not call `metamon.forall*`
concurrently — start one, wait for it, start the next. On the BEAM
target every test runs in its own process, so the issue does not
arise.

## UTF-8 surrogate range is excluded from `string_unicode`

`generator.string_unicode(len)` and `generator.unicode_codepoint()`
produce valid UTF-8 scalar values only. The surrogate range
`[0xD800, 0xDFFF]` is intentionally excluded because Gleam strings are
UTF-8 — lone surrogates would not survive
`string.from_utf_codepoints`. Lone surrogates, overlong encodings,
truncated continuation bytes, and other malformed UTF-8 byte sequences
cannot exist inside a Gleam `String`, so a parser-hardening property
that must accept or reject malformed UTF-8 input cannot reach those
bytes through `string_unicode`.

Workaround: drop down to `bit_array(byte_len)` and operate at the byte
level instead.

## No built-in bias toward Unicode normalisation boundaries

Equivalent forms like `"é" (U+00E9)` and `"e\u{0301}" (U+0065 U+0301)`
are sampled independently from `string_unicode`.

Workaround: pre-compose equivalence-class edges via `with_examples` if
your property depends on NFC vs NFD distinctions.

## `generator.float` is finite-only

`generator.float(lo, hi)` never emits `NaN`, `±Infinity`, or denormal
values. For codec / serialisation work where IEEE 754 special values
are part of the input space (and where the failure modes — `NaN != NaN`
breaking round-trips, `Infinity` formatting as `"Infinity"` in
`f64.to_string`, `-0.0` round-tripping differently than `0.0`) must be
exercised, reach for `generator.float_special()` or splice the eight
special values into a range generator via
`with_examples(my_float_gen, generator.float_special_edges())`.
Compose with `forall_round_trip_under` and a NaN-aware relation if
your property body needs to ignore NaN inputs explicitly.

## Float special values differ between targets

On JavaScript, `float_special` emits genuine `NaN` / `±Infinity` from
`Number.{NaN, POSITIVE_INFINITY, NEGATIVE_INFINITY}`. On the BEAM, the
same slots return finite sentinels (largest finite double, with the
appropriate sign) because the BEAM has no portable way to construct
non-finite IEEE 754 doubles from pure Erlang — `<<F/float>>` patterns,
`binary_to_term/1` with `NEW_FLOAT_EXT`, and `binary_to_float/1` all
reject NaN / ±Infinity bit patterns.

Workaround: properties that strictly require genuine non-finite inputs
must run on the JavaScript target; the BEAM run will exercise the
finite anchors only.
