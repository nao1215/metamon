-module(mutation_test_ffi).
-export([on_erlang/1, home/0]).

on_erlang(Run) -> Run().

home() -> unicode:characters_to_binary(os:getenv("HOME", "")).
