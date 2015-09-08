-module(zraft_test).

%% API
-export([
  run/2
]).

-define(TIMEOUT, 5000).


%% ---------------------------------------------------------------------
%% API
%% ---------------------------------------------------------------------

-spec run(pos_integer(), pos_integer()) -> ok.
run(NumberOfNodes, CommandSequenceLength) when NumberOfNodes > 1 andalso CommandSequenceLength > 0 ->
  Cluster = [zraft_node:create(1)],
  UnusedNodes = [zraft_node:create(I) || I <- lists:seq(2, NumberOfNodes)],
  UpNodes = Cluster,
  ok = zraft_cluster:create(Cluster),
  Value = new_value(UpNodes),
  run_commands(Cluster, UnusedNodes, UpNodes, Value, CommandSequenceLength).


%% ---------------------------------------------------------------------
%% Running commands
%% ---------------------------------------------------------------------

run_commands(_, _, _, _, 0) ->
  io:format("yay - full test done!");
run_commands(Cluster, UnusedNodes, UpNodes, Value, CommandsLeft) ->
  io:format(
        "~n~n--------------------------------------------------------------------------------~n~n" ++
            "Commands left: ~p~nCluster: ~p~nCurrent value: ~p~nChecking values in cluster...",
        [ CommandsLeft, [ {Node, lists:member(Node, UpNodes)} || Node <- Cluster ], Value ]
      ),
  check_values_in_cluster(UpNodes, Value),
  io:format("done~n"),
  {NewCluster, NewUnusedNodes, NewUpNodes, NewValue} = case random:uniform(10) of
    1 -> add_node_to_cluster(Cluster, UnusedNodes, UpNodes, Value);
    2 -> remove_node_from_cluster(Cluster, UnusedNodes, UpNodes, Value);
    3 -> boot_node(Cluster, UnusedNodes, UpNodes, Value);
    4 -> halt_node(Cluster, UnusedNodes, UpNodes, Value);
    _ -> {Cluster, UnusedNodes, UpNodes, new_value(UpNodes)}
  end,
  run_commands(NewCluster, NewUnusedNodes, NewUpNodes, NewValue, CommandsLeft-1).

add_node_to_cluster(Cluster, [], UpNodes, Value) ->
  {Cluster, [], UpNodes, Value};
add_node_to_cluster(Cluster, UnusedNodes, UpNodes, Value) ->
  Node = random_choose(UnusedNodes),
  io:format("try to add node ~p~n", [Node]),
  NewCluster = lists:sort([Node|Cluster]),
  case zraft_cluster:switch(NewCluster, Cluster, UpNodes) of
    ok ->
      {NewCluster, UnusedNodes -- [Node], lists:sort([Node|UpNodes]), Value};
    {error, Reason} ->
      io:format("could add node to cluster: ~p~n", [Reason]),
      timer:sleep(500),
      add_node_to_cluster(Cluster, UnusedNodes, UpNodes, Value)
  end.

remove_node_from_cluster(Cluster, UnusedNodes, UpNodes, Value) ->
  case (length(UpNodes) - 1) * 2 > length(Cluster) - 1 of
    true ->
      Node = random_choose(UpNodes),
      io:format("try to remove node ~p~n", [Node]),
      NewCluster = Cluster -- [Node],
      case zraft_cluster:switch(NewCluster, Cluster, UpNodes) of
        ok ->
          {NewCluster, lists:sort([Node|UnusedNodes]), UpNodes -- [Node], Value};
        {error, Reason} ->
          io:format("could remove node from cluster: ~p~n", [Reason]),
          timer:sleep(500),
          remove_node_from_cluster(Cluster, UnusedNodes, UpNodes, Value)
      end;
    false ->
      {Cluster, UnusedNodes, UpNodes, Value}
  end.

boot_node(Cluster, UnusedNodes, UpNodes, Value) ->
  case Cluster -- UpNodes of
    [] ->
      {Cluster, UnusedNodes, UpNodes, Value};
    DownNodes ->
      Node = random_choose(DownNodes),
      io:format("try to boot node ~p~n", [Node]),
      zraft_instance:start_instance(Node),
      {Cluster, UnusedNodes, lists:sort([Node|UpNodes]), Value}
  end.

halt_node(Cluster, UnusedNodes, UpNodes, Value) ->
  case (length(UpNodes) - 1) * 2 > length(Cluster) of
    true ->
      Node = random_choose(UpNodes),
      io:format("try to halt node ~p~n", [Node]),
      zraft_instance:halt_instance(Node),
      {Cluster, UnusedNodes, UpNodes -- [Node], Value};
    false ->
      {Cluster, UnusedNodes, UpNodes, Value}
  end.

random_choose(Nodes) ->
  I = random:uniform(length(Nodes)),
  lists:nth(I, Nodes).



%% ---------------------------------------------------------------------
%% Writing and reading values
%% ---------------------------------------------------------------------

new_value(UpNodes) ->
  Value = random:uniform(),
  write_value_to_cluster(UpNodes, 1, Value),
  write_value_to_cluster(UpNodes, 2, Value+1),
  Value.

write_value_to_cluster([ZraftNode|_]=UpNodes, Key, Value) ->
  case rpc:call(zraft_node:node(ZraftNode), zraft_client, write,
      [zraft_node:zraft_name(ZraftNode), {Key, Value}, ?TIMEOUT]) of
    {ok, _} -> ok;
    _Otherwise -> write_value_to_cluster(UpNodes, Key, Value)
  end.

check_values_in_cluster(UpNodes, Value) ->
  true = check_value_in_cluster(UpNodes, 1, Value),
  true = check_value_in_cluster(UpNodes, 2, Value+1).

check_value_in_cluster(UpNodes, Key, Value) ->
  [Value || _ <- UpNodes] == read_value_from_cluster(UpNodes, Key).

read_value_from_cluster(UpNodes, Key) ->
  [
    begin
      io:format("{~p, ~p}...", [Node, Key]),
      read_value_from_node(Node, Key)
    end
  ||
    Node <- UpNodes
  ].

read_value_from_node(ZraftNode, Key) ->
  Self = self(),
  Pid = spawn_link(zraft_node:node(ZraftNode), fun() -> read_value_from_node_process(ZraftNode, Key, Self) end),
  receive
    {value, Pid, Value} -> Value
  end.

read_value_from_node_process(ZraftNode, Key, Master) ->
  case zraft_session:start_link(zraft_node:zraft_name(ZraftNode), ?TIMEOUT) of
    {ok, Session} ->
      Value = read_value_from_node_process_loop(Session, Key),
      Master ! {value, self(), Value},
      ok;
    Otherwise ->
      io:format("got result ~p~n", [Otherwise]),
      read_value_from_node_process(ZraftNode, Key, Master)
  end.

read_value_from_node_process_loop(Session, Key) ->
  case zraft_session:query(Session, Key, watching, ?TIMEOUT) of
    {ok, Value} ->
      Value;
    {error, timeout} ->
      read_value_from_node_process_loop(Session, Key);
    Otherwise1 ->
      io:format("got result ~p~n", [Otherwise1]),
      receive
        {swatch_trigger, watching, {data_changed, Value}} ->
          Value;
        Otherwise2 ->
          io:format("got event ~p~n", [Otherwise2]),
          read_value_from_node_process_loop(Session, Key)
      end
  end.
