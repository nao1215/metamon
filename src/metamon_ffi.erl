-module(metamon_ffi).

-export([
    now_microseconds/0,
    codepoint_to_string/1,
    state_put/2,
    state_get/1,
    state_erase/1,
    state_keys/0,
    identity/1,
    capture_panic/1
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
