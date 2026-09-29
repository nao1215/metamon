-module(metamon_env_test_ffi).

-export([set_env/2, unset_env/1, count_reset/0, count_bump/0, count_get/0]).

%% Environment and a call counter for runs_multiplier_test.gleam.

set_env(Name, Value) ->
    true = os:putenv(unicode:characters_to_list(Name), unicode:characters_to_list(Value)),
    nil.

unset_env(Name) ->
    true = os:unsetenv(unicode:characters_to_list(Name)),
    nil.

count_reset() ->
    erlang:put(metamon_env_test_count, 0),
    nil.

count_bump() ->
    erlang:put(metamon_env_test_count, count_get() + 1),
    nil.

count_get() ->
    case erlang:get(metamon_env_test_count) of
        undefined -> 0;
        N -> N
    end.
