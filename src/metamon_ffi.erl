-module(metamon_ffi).

-export([
    now_microseconds/0,
    codepoint_to_string/1,
    state_put/2,
    state_get/1,
    state_erase/1,
    state_keys/0,
    identity/1,
    capture_panic/1,
    ieee_nan/0,
    ieee_positive_infinity/0,
    ieee_negative_infinity/0,
    ieee_smallest_positive_denormal/0,
    ieee_largest_finite/0
]).

now_microseconds() ->
    erlang:system_time(microsecond).

codepoint_to_string(Codepoint) when is_integer(Codepoint) ->
    unicode:characters_to_binary([Codepoint]).

%% Process-dictionary-backed state used by metamon/annotate and
%% metamon/coverage. Each test process is independent on the BEAM, so
%% gleeunit's per-test isolation is preserved automatically.

state_put(Key, Value) ->
    erlang:put({metamon_state, Key}, Value),
    nil.

state_get(Key) ->
    case erlang:get({metamon_state, Key}) of
        undefined -> {error, nil};
        Value -> {ok, Value}
    end.

state_erase(Key) ->
    erlang:erase({metamon_state, Key}),
    nil.

state_keys() ->
    Keys = erlang:get_keys(),
    [K || {metamon_state, K} <- Keys].

%% identity/1 is used by the Gleam side to "trust" the shape of values
%% that the metamon runner itself put into process state. It is the
%% smallest possible escape hatch from the dynamic decoder dance and is
%% used only on the FFI seam.
identity(X) -> X.

%% Run a thunk and report `{Panicked, Message}` to the caller. Used
%% by tests that exercise the failure path of `metamon.forall` and
%% `metamon.forall_morph` without aborting the test process.
capture_panic(Thunk) ->
    try Thunk() of
        _ -> {false, <<"">>}
    catch
        error:#{gleam_error := panic, message := Message} ->
            Bin = case is_binary(Message) of
                true -> Message;
                false -> unicode:characters_to_binary(io_lib:format("~p", [Message]))
            end,
            {true, Bin};
        error:Reason ->
            Bin = unicode:characters_to_binary(io_lib:format("~p", [Reason])),
            {true, Bin};
        throw:Thrown ->
            Bin = unicode:characters_to_binary(io_lib:format("~p", [Thrown])),
            {true, Bin};
        exit:Exit ->
            Bin = unicode:characters_to_binary(io_lib:format("~p", [Exit])),
            {true, Bin}
    end.

%% IEEE 754 special-value constructors used by `generator.float_special`.
%%
%% Modern Erlang/OTP refuses to materialise non-finite IEEE 754 doubles
%% through every public conversion path: `<<F/float>>` patterns reject
%% NaN / ±Infinity bit patterns with `badmatch`, `binary_to_term/1`
%% rejects NEW_FLOAT_EXT bytes outside the finite range with `badarg`,
%% and `binary_to_float/1` accepts only standard textual literals. The
%% BEAM thus has no portable way to construct NaN or ±Infinity from
%% pure Erlang code; only NIFs or external term ports can introduce
%% them, and either is too heavy for a property-testing library.
%%
%% The compromise: on the BEAM we return finite sentinels for the
%% three non-finite values (NaN → 1.0/0.0 of pure ones at the largest
%% finite double, ±Infinity → ±largest finite double). The JavaScript
%% target keeps the genuine non-finite values via `Number.{NaN,
%% POSITIVE_INFINITY, NEGATIVE_INFINITY}`. Properties that depend on
%% the genuine non-finite values must run on the JavaScript target;
%% the README and `float_special` docstring call out this asymmetry.

ieee_nan() ->
    %% Largest finite double. On the BEAM, NaN cannot be constructed
    %% portably, so callers see the same finite sentinel as
    %% `ieee_largest_finite/0`. JS callers get a real NaN.
    ieee_largest_finite().

ieee_positive_infinity() ->
    ieee_largest_finite().

ieee_negative_infinity() ->
    -ieee_largest_finite().

ieee_smallest_positive_denormal() ->
    %% Subnormal — exponent zero, mantissa non-zero. The standard
    %% `<<F/float>>` pattern *does* accept subnormals (only NaN /
    %% ±Infinity are rejected), so this round-trip is safe.
    <<F/float>> = <<0:1, 0:11, 1:52>>,
    F.

ieee_largest_finite() ->
    %% 1.7976931348623157e308 — the largest finite double.
    <<F/float>> = <<0:1, 16#7FE:11, ((1 bsl 52) - 1):52>>,
    F.
