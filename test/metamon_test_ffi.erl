-module(metamon_test_ffi).

-export([capture_panic/1]).

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
