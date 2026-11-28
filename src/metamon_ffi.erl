-module(metamon_ffi).

-export([
    now_microseconds/0,
    codepoint_to_string/1,
    state_put/2,
    state_get/1,
    state_erase/1,
    identity/1,
    ieee_nan/0,
    ieee_positive_infinity/0,
    ieee_negative_infinity/0,
    ieee_smallest_positive_denormal/0,
    ieee_largest_finite/0,
    getenv/1,
    capture_panic/1,
    plain_arguments/0,
    parallel_map/2,
    monotonic_milliseconds/0,
    find_executable/1,
    run_command/4,
    measure_coverage/0
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

%% identity/1 is used by the Gleam side to "trust" the shape of values
%% that the metamon runner itself put into process state. It is the
%% smallest possible escape hatch from the dynamic decoder dance and is
%% used only on the FFI seam.
identity(X) -> X.

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
%% the `float_special` documentation calls out this asymmetry.

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

%% Read an environment variable as `{ok, Binary}`, or `{error, nil}` when it
%% is unset. Used for METAMON_RUNS_MULTIPLIER.
getenv(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

%% Run a thunk and return `{false, Value}` with its result, or
%% `{true, Message}` when it raises. A Gleam panic, `assert` or `let assert` carries its message in
%% the error map; any other error, throw or exit is formatted with `~p`.
capture_panic(Thunk) ->
    try Thunk() of
        Value -> {false, Value}
    catch
        error:#{gleam_error := _, message := Message} when is_binary(Message) ->
            {true, Message};
        _:Reason ->
            {true, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% Mutation testing (metamon/mutation).

%% The arguments after `--` of `gleam run -m metamon/mutation -- ...`.
plain_arguments() ->
    [unicode:characters_to_binary(Argument) || Argument <- init:get_plain_arguments()].

%% Apply Fun to every item in its own process and return the results in order.
parallel_map(Items, Fun) ->
    Parent = self(),
    Refs = [begin
                Ref = make_ref(),
                spawn_link(fun() -> Parent ! {Ref, Fun(Item)} end),
                Ref
            end || Item <- Items],
    [receive {Ref, Result} -> Result end || Ref <- Refs].

monotonic_milliseconds() ->
    erlang:monotonic_time(millisecond).

find_executable(Name) ->
    case os:find_executable(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, unicode:characters_to_binary(Path)}
    end.

%% Run Executable with Arguments in Directory and return {ok, {Status, Output}}
%% with stdout and stderr combined, or {error, nil} when it is not on PATH.
run_command(Executable, Arguments, Directory, Environment) ->
    case os:find_executable(unicode:characters_to_list(Executable)) of
        false ->
            {error, nil};
        Path ->
            Port = open_port(
                {spawn_executable, Path},
                [{args, [unicode:characters_to_list(A) || A <- Arguments]},
                 {cd, unicode:characters_to_list(Directory)},
                 {env, [{unicode:characters_to_list(Name), unicode:characters_to_list(Value)}
                        || {Name, Value} <- Environment]},
                 exit_status, stderr_to_stdout, binary, hide, use_stdio]
            ),
            collect_output(Port, <<>>, <<>>, 0)
    end.

%% A mutant that prints in a loop must not fill the runner's memory, so only
%% the start and the end of the output are kept: a compile error is at the
%% start and the test summary at the end.
-define(OUTPUT_KEPT, 65536).

collect_output(Port, Head, Tail, Dropped) ->
    receive
        {Port, {data, Data}} when byte_size(Head) < ?OUTPUT_KEPT ->
            Room = ?OUTPUT_KEPT - byte_size(Head),
            case Data of
                <<Start:Room/binary, Rest/binary>> ->
                    keep_tail(Port, <<Head/binary, Start/binary>>, Tail, Rest, Dropped);
                _ ->
                    collect_output(Port, <<Head/binary, Data/binary>>, Tail, Dropped)
            end;
        {Port, {data, Data}} ->
            keep_tail(Port, Head, Tail, Data, Dropped);
        {Port, {exit_status, Status}} ->
            Gap = case Dropped of
                0 -> <<>>;
                _ -> iolist_to_binary(
                         io_lib:format("~n[~B bytes of output left out]~n", [Dropped]))
            end,
            {ok, {Status, <<Head/binary, Gap/binary, Tail/binary>>}}
    end.

keep_tail(Port, Head, Tail, Data, Dropped) ->
    Joined = <<Tail/binary, Data/binary>>,
    case byte_size(Joined) - ?OUTPUT_KEPT of
        Excess when Excess > 0 ->
            <<_:Excess/binary, Kept/binary>> = Joined,
            collect_output(Port, Head, Kept, Dropped + Excess);
        _ ->
            collect_output(Port, Head, Joined, Dropped)
    end.

%% Run by `gleam run -m metamon/mutation -- coverage` in a fresh `erl`, so
%% that a test cannot stop the command and the modules of the command are not
%% replaced while it runs. The plain arguments are the file to write, the
%% modules to measure, `--` and the test modules. Each line of the file is
%% "module<TAB>line<TAB>calls". Halts with 0 when every test passes, 1 when
%% one fails and 2 when the measuring itself fails.
measure_coverage() ->
    try
        [Output | Rest] = init:get_plain_arguments(),
        {Measured, ["--" | Tests]} = lists:splitwith(fun(A) -> A =/= "--" end, Rest),
        cover:start(),
        Modules = [M || {ok, M} <- [cover:compile_beam(list_to_atom(N)) || N <- Measured]],
        Result = eunit:test([list_to_atom(T) || T <- Tests], [{scale_timeouts, 10}]),
        Lines = [io_lib:format("~s\t~B\t~B~n", [M, Line, Calls])
                 || M <- Modules,
                    {ok, Counts} <- [cover:analyse(M, calls, line)],
                    {{_, Line}, Calls} <- Counts,
                    Line > 0],
        ok = file:write_file(Output, Lines),
        halt(case Result of ok -> 0; _ -> 1 end)
    catch
        Class:Reason:Stacktrace ->
            io:format(standard_error, "~p~n", [{Class, Reason, Stacktrace}]),
            halt(2)
    end.
