#!/usr/bin/env escript
-define(SHOULD_LOG, false).
-define(SIMULATION_COUNT, 1000).

-define(INITIAL_GROW_PERIOD, 28).
-define(FURTHER_GROW_PERIOD, 7).

main([DesiredCountStr | StartingSeedsStrs]) ->
    DesiredCount = list_to_integer(DesiredCountStr),
    StartingSeeds = [list_to_integer(StartingSeedStr) || StartingSeedStr <- StartingSeedsStrs],
    Results = concurrent_map(fun(_) -> simulation(DesiredCount, StartingSeeds) end, lists:seq(1, ?SIMULATION_COUNT)),
    ResultsCountMap = lists:foldl(fun(Result, CountMap) ->
        case CountMap of
            #{Result := ResultCount} ->
                CountMap#{Result => ResultCount + 1};
            _ ->
                CountMap#{Result => 1}
        end
    end, #{}, Results),
    lists:foreach(fun({Result, Count}) ->
        io:format("~p: ~p%~n", [Result, 100 * (Count / ?SIMULATION_COUNT)])
    end, lists:sort(maps:to_list(ResultsCountMap))),
    halt(0).
    
simulation(DesiredCount, StartingSeeds) ->
    This = self(),
    Subprocesses = [spawn_link(fun() -> seed_loop(This, Seed) end) || Seed <- StartingSeeds],
    simulation_loop(DesiredCount, 1, Subprocesses).
    
simulation_loop(DesiredCount, DayCount, Subprocesses) ->
    NewDayCount = DayCount + 1,
    log("Day ~p start~n", [NewDayCount]),
    lists:foreach(fun(Subprocess) ->
        Subprocess ! day
    end, Subprocesses),
    NewSubprocesses = Subprocesses ++ lists:append([simulation_receive(Subprocess) || Subprocess <- Subprocesses]),
    case length(NewSubprocesses) of
        N when N >= DesiredCount -> NewDayCount;
        _ -> simulation_loop(DesiredCount, NewDayCount, NewSubprocesses)
    end.

simulation_receive(PID) ->
    receive
        {PID, another} -> 
            new_seeds_gen();
        {PID, nothing} -> 
            []
    end.

seed_loop(Parent, Cooldown) ->
    {Reply, UpdatedCooldown} = case Cooldown of
        1 -> {another, ?FURTHER_GROW_PERIOD};
        _ -> {nothing, Cooldown - 1}
    end,
    receive
        day ->
            log("~p: ~p~n", [self(), UpdatedCooldown]),
            Parent ! {self(), Reply}
    end,
    seed_loop(Parent, UpdatedCooldown).

new_seeds_gen() ->
    Count = case 100 * rand:uniform() of
        N when N =< 1.99 ->
            log("Crap! No new seeds.~n"),
            0;
        N when N =< 2.49 ->
            log("New seed!~n"),
            1;
        _ ->
            case rand:uniform(3) of
                1 ->
                    log("New seed!~n"),
                    1;
                N ->
                    log("~p new seeds!~n", [N]),
                    N
            end
    end,
    This = self(),
    [spawn_link(fun() -> seed_loop(This, ?INITIAL_GROW_PERIOD) end) || _ <- lists:seq(1, Count)].

%%%%%

log(Str) ->
    log(Str, []).

log(Str, Params) ->
    case ?SHOULD_LOG of
        true -> io:format(Str, Params);
        _ -> nothing
    end.

concurrent_map(Fun, List) ->
    Listen = fun 
        Listen([H | T]) ->
            receive
                {H, Val} -> [Val | Listen(T)]
            end;
        Listen([]) ->
            []
    end,
    Pid = self(),
    Listen(lists:map(fun(Ele) ->
        spawn(fun() ->
            Pid ! {self(), Fun(Ele)}
        end)
    end, List)).