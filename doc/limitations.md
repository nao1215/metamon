# Limitations

What metamon does not do, and how to work around it.

## `Transform(a)` is `fn(a) -> a`

A transform cannot change the type of its input, so `String -> Result(Spec, Error)` cannot be an input transform. Make the type change part of the function under test and use an `Equivariant` morph, or a plain `forall`.

## `Relation(b)` compares two `b` values

A relation between an input and an output, such as "the output is no longer than the input", is not a `Relation`. Write it as a `forall` property that closes over both values.

## `bind` shrinks shallowly

A generator built with `bind` shrinks the outer value, but the inner value only shrinks within the first inner generator, so a shrunk failure may show an inner value that is not minimal. Prefer `map2` to `map6` and `tuple2` to `tuple6` when the inner shape does not depend on the outer value.

## `recursive` does not swap branches while shrinking

A failing `Node(left, right)` does not reduce to `left` or `right`; only the leaves shrink. List the small shapes with `with_examples` so they are tried first.

## Examples do not shrink

A value listed with `with_examples` is reported as it is when it fails, with `shrinks: 0`, because it is the caller's own input. The built-in edge values shrink like random inputs.

## Shrinking keeps the panic message

A smaller input is kept only when it panics with the same message as the original failure, so the report never mixes one failure's input with another failure's message. A message that contains the input, such as `panic as { "got " <> int.to_string(n) }`, differs for every input and stops shrinking at the first failing input. Put the value in `annotate` and keep the message fixed.

## `filter` panics after 100 consecutive rejections

A predicate that accepts less than about 1% of the generated values makes `filter` panic. Narrow the generator instead, for example `int(range(from: 0, to: 9))` rather than filtering `int(range(from: -100, to: 100))`.

## One property at a time on JavaScript

`classify`, `cover` and `annotate` keep their state in a module-level `Map` on JavaScript. Test files run in separate workers, so files can run in parallel, but do not run two properties concurrently in one file. On Erlang each test runs in its own process.

## Strings hold valid UTF-8 only

`string(of: Unicode, ..)` and `character(of: Unicode)` produce Unicode scalar values only. A Gleam `String` cannot hold lone surrogates or malformed UTF-8, so test byte-level parsers with `bit_array(bytes: ..)`.

## No bias toward normalisation boundaries

`"é"` (U+00E9) and `"e\u{0301}"` are generated independently. Add equivalent forms with `with_examples` if a property depends on NFC and NFD.

## `float` is finite only

`float(from:, to:)` never produces NaN or infinities. Use `float_special()` for them and for the smallest subnormal value. On Erlang, `float_special()` returns the largest finite floats in place of NaN and the infinities, because the BEAM cannot build non-finite floats; properties that need real non-finite values must run on JavaScript.

## Dependencies

metamon depends on `gleam_stdlib`, `simplifile` and `gleam_json`. `simplifile` is used only when `Config.regression_file` is set, and `gleam_json` only when `Config.output` is `Json`.
