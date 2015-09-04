-module(zraft_cluster).

%% API
-export([
  create/1,
  switch/3
]).

-define(TIMEOUT, 5000).


%% ---------------------------------------------------------------------
%% API
%% ---------------------------------------------------------------------

-spec create([zraft_node:zraft_node()]) -> ok | {error, term()}.
create([First|_]=Nodes) ->
  FirstNode = zraft_node:node(First),
  ZraftNames = [zraft_node:zraft_name(Node) || Node <- Nodes],
  [zraft_instance:start_instance(Node) || Node <- Nodes],
  timer:sleep(1000),
  case rpc:call(FirstNode, zraft_client, create, [ZraftNames, zraft_dict_backend]) of
    {ok, _} -> ok;
    {error, _Reason}=Error -> Error;
    Otherwise -> {error, Otherwise}
  end.

-spec switch([zraft_node:zraft_node()], [zraft_node:zraft_node()], [zraft_node:zraft_node()]) ->
    ok | {error, term()}.
switch(NewCluster, OldCluster, OldUpNodes) ->
  AddedNodes = NewCluster -- OldCluster,
  RemovedNodes = OldCluster -- NewCluster,
  [PeerNode|_] = OldUpNodes -- RemovedNodes,
  start_instances(AddedNodes),
  io:format("zraft_cluster:switch(): using peer-node ~p~n", [PeerNode]),
  case rpc:call(zraft_node:node(PeerNode), zraft_client, set_new_conf, [
        zraft_node:zraft_name(PeerNode),
        [zraft_node:zraft_name(Node) || Node <- NewCluster],
        [zraft_node:zraft_name(Node) || Node <- OldCluster],
        ?TIMEOUT
      ]) of
    {ok, _} ->
      [zraft_instance:remove_instance(Node) || Node <- RemovedNodes],
      ok;
    {error, _Reason}=Error ->
      Error;
    Otherwise ->
      {error, Otherwise}
  end.


%% ---------------------------------------------------------------------
%% Internal functions
%% ---------------------------------------------------------------------

start_instances([]) ->
  ok;
start_instances([Node|Rest]) ->
  case net_adm:ping(zraft_node:node(Node)) of
    pong ->
      start_instances(Rest);
    pang ->
      start_instance(Node),
      start_instances(Rest)
  end.

start_instance(Node) ->
  zraft_instance:start_instance(Node),
  timer:sleep(1000),
  {ok, _} = rpc:call(zraft_node:node(Node), zraft_lib_sup, start_consensus,
      [zraft_node:zraft_name(Node), zraft_dict_backend]),
  timer:sleep(1000).
