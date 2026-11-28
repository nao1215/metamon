-module(metamon_e2e).

%% Line coverage of an end-to-end suite, for
%% `gleam run -m metamon/mutation -- coverage --e2e COMMAND`.
%%
%% The suite starts the program many times. Compiling it under `cover` on
%% every start took 6.5 seconds for oaspec, so `prepare/0` compiles the
%% package's modules once into a directory and writes an escript there that
%% runs the program from them. Each start then only loads the modules, and
%% the runtime counts the lines they run.
%%
%% The program ends with `erlang:halt` or `init:stop`, which stop the runtime
%% before anything else can read the counts, so `prepare/0` replaces each such
%% call in the package's modules by a call to `halt/2` here, which writes the
%% counts of that run to a file of its own and then halts.

-export([prepare/0, main/1, halt/0, halt/1, halt/2]).

-compile({no_auto_import, [halt/0, halt/1, halt/2]}).

%% Run in a fresh `erl` with the paths of the built packages. The plain
%% arguments are the directory to write, the package, the modules to measure,
%% `--` and the other modules of the package (its Erlang files), whose calls
%% to halt are replaced but whose lines are not counted. Writes
%% DIRECTORY/bin/PACKAGE, the escript, and halts with 0, or with 2 when a
%% module cannot be compiled.
prepare() ->
    try
        [Dir, Package | Rest] = init:get_plain_arguments(),
        {Measured, ["--" | Others]} = lists:splitwith(fun(A) -> A =/= "--" end, Rest),
        Ebin = filename:join(Dir, "ebin"),
        Bin = filename:join(Dir, "bin"),
        ok = filelib:ensure_path(Ebin),
        ok = filelib:ensure_path(Bin),
        ok = filelib:ensure_path(filename:join(Dir, "counts")),
        Jobs = [{list_to_atom(M), counted} || M <- Measured]
            ++ [{list_to_atom(M), plain} || M <- [Package ++ "@@main" | Others]],
        %% Each module is compiled in a process of its own, and a failure comes
        %% back as a value so that the catch below reports it.
        Parent = self(),
        Refs = [begin
                    Ref = make_ref(),
                    spawn(fun() ->
                        Result = try prepare_module(M, How, Ebin)
                                 catch C:R:S -> {error, {M, C, R, S}}
                                 end,
                        Parent ! {Ref, Result}
                    end),
                    Ref
                end || {M, How} <- Jobs],
        [ok = receive {Ref, Result} -> Result end || Ref <- Refs],
        %% The `-pa` directories, in the order `erl` searches them.
        Root = code:root_dir(),
        Paths = [filename:absname(P) || P <- code:get_path(),
                                        P =/= ".",
                                        not lists:prefix(Root, filename:absname(P))],
        Config = [{package, Package},
                  {paths, Paths},
                  {measured, [list_to_atom(M) || M <- Measured]}],
        ok = file:write_file(filename:join(Dir, "config"),
                             [io_lib:format("~p.~n", [Term]) || Term <- Config]),
        %% The escript holds this module and starts in main/1. argv reads
        %% the arguments of an escript only when `-escript` is among the
        %% emulator arguments, as in the escripts gleescript writes.
        {?MODULE, Beam, _} = code:get_object_code(?MODULE),
        Escript = filename:join(Bin, Package),
        ok = escript:create(Escript, [
            shebang,
            {comment, "Runs " ++ Package ++ " with its lines counted, for metamon's coverage command."},
            {emu_args, "-escript main " ++ atom_to_list(?MODULE)},
            {beam, Beam}
        ]),
        ok = file:change_mode(Escript, 8#755),
        erlang:halt(0)
    catch
        Class:Reason:Stacktrace ->
            io:format(standard_error, "~p~n", [{Class, Reason, Stacktrace}]),
            erlang:halt(2)
    end.

%% Compile Module again from the abstract code in its BEAM file, with its
%% calls to halt replaced, and write it to Ebin. `force_line_counters` makes
%% the runtime count the lines of a counted module, as `cover` does; the
%% abstract code stays in the file so that `cover` can measure the module on a
%% runtime without native coverage.
prepare_module(Module, How, Ebin) ->
    {ok, {Module, [{abstract_code, {raw_abstract_v1, Code}}]}} =
        beam_lib:chunks(code:which(Module), [abstract_code]),
    %% Gleam marks each function with a `-file` attribute for its `.gleam`
    %% file, and the compiler counts only the lines of the first file it
    %% sees, the generated `.erl`. `cover` moves the attributes into the
    %% annotations first, and so does this.
    Forms = epp:interpret_file_attribute(Code),
    Defined = [{Name, Arity} || {function, _, Name, Arity, _} <- Forms],
    Options = [binary, return_errors, debug_info] ++ case How of
        counted -> [line_coverage, force_line_counters];
        plain -> []
    end,
    {ok, Module, Binary} = compile:forms(replace_halt(Forms, Defined), Options),
    file:write_file(filename:join(Ebin, atom_to_list(Module) ++ ".beam"), Binary).

replace_halt({call, A, {remote, _, {atom, _, erlang}, {atom, _, halt}}, Args}, Defined)
  when length(Args) =< 2 ->
    halt_call(A, Args, Defined);
replace_halt({call, A, {remote, _, {atom, _, init}, {atom, _, stop}}, Args}, Defined)
  when length(Args) =< 1 ->
    halt_call(A, Args, Defined);
replace_halt({call, A, {atom, _, halt}, Args} = Call, Defined) when length(Args) =< 2 ->
    %% A local call to halt is the BIF unless the module defines its own.
    case lists:member({halt, length(Args)}, Defined) of
        true -> setelement(4, Call, replace_halt(Args, Defined));
        false -> halt_call(A, Args, Defined)
    end;
replace_halt(Term, Defined) when is_tuple(Term) ->
    list_to_tuple(replace_halt(tuple_to_list(Term), Defined));
replace_halt(Terms, Defined) when is_list(Terms) ->
    [replace_halt(T, Defined) || T <- Terms];
replace_halt(Term, _) ->
    Term.

halt_call(A, Args, Defined) ->
    {call, A, {remote, A, {atom, A, ?MODULE}, {atom, A, halt}},
     replace_halt(Args, Defined)}.

%% The escript that `prepare/0` writes starts here. It puts the compiled
%% modules before the built ones and runs the program as `gleam run` does,
%% with the arguments it was given.
main(_) ->
    %% The suite may run a copy or a link of the escript, so the directory
    %% comes from the variable the coverage command sets when there is one.
    Escript = case os:getenv("METAMON_COVERAGE_ESCRIPT") of
        false -> filename:absname(escript:script_name());
        Path -> Path
    end,
    Dir = filename:dirname(filename:dirname(Escript)),
    {ok, Config} = file:consult(filename:join(Dir, "config")),
    Package = proplists:get_value(package, Config),
    Measured = proplists:get_value(measured, Config),
    %% add_pathsa puts the last directory first.
    ok = code:add_pathsa(lists:reverse(proplists:get_value(paths, Config))),
    true = code:add_patha(filename:join(Dir, "ebin")),
    Native = code:coverage_support(),
    case Native of
        true -> ok;
        false -> {ok, _} = cover:start(), cover:compile_beam(Measured)
    end,
    persistent_term:put(?MODULE, {Dir, Measured, Native}),
    Main = list_to_atom(Package ++ "@@main"),
    Main:run(list_to_atom(Package)).

halt() ->
    halt(0, []).

halt(Status) ->
    halt(Status, []).

%% Write the counts of this run, one "module<TAB>line<TAB>calls" per line as
%% `metamon_ffi:measure_coverage/0` does, then halt.
halt(Status, Options) ->
    case persistent_term:get(?MODULE, undefined) of
        {Dir, Measured, Native} ->
            Lines = [io_lib:format("~s\t~B\t~B~n", [M, Line, Calls])
                     || M <- Measured,
                        code:is_loaded(M) =/= false,
                        {Line, Calls} <- line_counts(M, Native),
                        Line > 0],
            %% The process id alone repeats over a long suite.
            Name = io_lib:format("~s-~B.tsv",
                                 [os:getpid(), os:system_time(nanosecond)]),
            _ = file:write_file(filename:join([Dir, "counts", Name]), Lines),
            ok;
        undefined ->
            ok
    end,
    erlang:halt(Status, Options).

line_counts(Module, true) ->
    code:get_coverage(line, Module);
line_counts(Module, false) ->
    {ok, Counts} = cover:analyse(Module, calls, line),
    [{Line, Calls} || {{_, Line}, Calls} <- Counts].
