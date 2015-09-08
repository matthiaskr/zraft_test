-module(zraft_instance).

%% API
-export([
  start_instance/1,
  stop_instance/1,
  halt_instance/1,
  remove_instance/1
]).

%% Internal API
-export([
  start_zraft_application/0
]).


%% -------------------------------------------------------------------
%% API
%% -------------------------------------------------------------------

-spec start_instance(zraft_node:zraft_node()) -> ok.
start_instance(ZraftNode) ->
  ensure_service_started(ZraftNode),
  Name = zraft_node:name(ZraftNode),
  Node = zraft_node:node(ZraftNode),
  Name ! {start, self()},
  receive
    {Name, start, Node} ->
      ok;
    {'EXIT', Reason} ->
      throw({'cannot start zraft instance', Reason})
  after 60000 ->
    throw({timeout, ?MODULE})
  end.

-spec stop_instance(zraft_node:zraft_node()) -> ok.
stop_instance(ZraftNode) ->
  ensure_service_started(ZraftNode),
  Name = zraft_node:name(ZraftNode),
  Name ! {stop, self()},
  receive
    {Name, stop} ->
      ok;
    {'EXIT', Reason} ->
      throw({'cannot stop zraft instance', Reason})
  after 60000 ->
    throw({timeout, ?MODULE})
  end.

-spec halt_instance(zraft_node:zraft_node()) -> ok.
halt_instance(ZraftNode) ->
  ensure_service_started(ZraftNode),
  Name = zraft_node:name(ZraftNode),
  Name ! {halt, self()},
  receive
    {Name, stop} ->
      ok;
    {'EXIT', Reason} ->
      throw({'cannot stop zraft instance', Reason})
  after 60000 ->
    throw({timeout, ?MODULE})
  end.

-spec remove_instance(zraft_node:zraft_node()) -> ok.
remove_instance(ZraftNode) ->
  ensure_service_started(ZraftNode),
  Name = zraft_node:name(ZraftNode),
  Name ! {halt, self()},
  receive
    {Name, stop} ->
      os:cmd("rm -rf ./data/" ++ atom_to_list(zraft_node:node(ZraftNode))),
      ok;
    {'EXIT', Reason} ->
      throw({'cannot stop zraft instance', Reason})
  after 60000 ->
    throw({timeout, ?MODULE})
  end.


%% -------------------------------------------------------------------
%% Internal functions
%% -------------------------------------------------------------------

ensure_service_started(ZraftNode) ->
  Name = zraft_node:name(ZraftNode),
  Node = zraft_node:node(ZraftNode),
  case whereis(Name) of
    undefined ->
      Pid = spawn_link(fun() ->
        port_master(Name, Node, os:getenv("ZRAFT_NODE_STDOUT") =:= "true", not_running)
      end),
      register(Name, Pid);
    _ ->
      ok
  end.

port_master(Name, Node, PrintNodeStdout, not_running) ->
  receive
    {start, Client} ->
      Port = open_port({spawn_executable, "./start-zraft-instance"},
          [{args, [Node]}, {line, 1024}, use_stdio, exit_status]),
      wait_for_instance(Node),
      start_zraft_application_on_instance(Node),
      Client ! {Name, start, Node},
      port_master(Name, Node, PrintNodeStdout, {running, Port});
    {stop, Client} ->
      Client ! {Name, stop},
      port_master(Name, Node, PrintNodeStdout, not_running);
    {halt, Client} ->
      Client ! {Name, halt},
      port_master(Name, Node, PrintNodeStdout, not_running);
    Message ->
      print_message(PrintNodeStdout, Message),
      port_master(Name, Node, PrintNodeStdout, not_running)
  end;
port_master(Name, Node, PrintNodeStdout, {running, Port}) ->
  receive
    {stop, Client} ->
      rpc:call(Node, init, stop, []),
      port_master(Name, Node, PrintNodeStdout, {shutdown, Port, Client});
    {halt, Client} ->
      rpc:cast(Node, erlang, halt, []),
      port_master(Name, Node, PrintNodeStdout, {shutdown, Port, Client});
    Message ->
      print_message(PrintNodeStdout, Message),
      port_master(Name, Node, PrintNodeStdout, {running, Port})
  end;
port_master(Name, Node, PrintNodeStdout, {shutdown, Port, Client}) ->
  receive
    {Port, {exit_status, _Status}} ->
      Client ! {Name, stop},
      port_master(Name, Node, PrintNodeStdout, not_running);
    {'EXIT', Port, _Reason} ->
      Client ! {Name, stop},
      port_master(Name, Node, PrintNodeStdout, not_running);
    Message ->
      print_message(PrintNodeStdout, Message),
      port_master(Name, Node, PrintNodeStdout, {shutdown, Port, Client})
  end.

print_message(false, _Message) -> ok;
print_message(true, {_, {data, {eol, String}}}) ->
  io:format("~s~n", [String]);
print_message(true, {_, {data, {noeol, String}}}) ->
  io:format("~s~n", [String]);
print_message(true, OtherData) ->
  io:format("~n~p~n", [OtherData]).

wait_for_instance(Node) ->
  wait_for_instance(Node, 100).

wait_for_instance(Node, 0) ->
  throw({'cannot connect to node', Node});
wait_for_instance(Node, N) ->
  case net_adm:ping(Node) of
    pong ->
      ok;
    pang ->
      timer:sleep(300),
      wait_for_instance(Node, N-1)
  end.

start_zraft_application_on_instance(Node) ->
  start_zraft_application_on_instance(Node, 100).

start_zraft_application_on_instance(Node, 0) ->
  throw({'cannot start zraft application on instance', Node});
start_zraft_application_on_instance(Node, N) ->
  case rpc:call(Node, ?MODULE, start_zraft_application, []) of
    {ok, _} ->
      ok;
    {error, _} ->
      timer:sleep(300),
      start_zraft_application_on_instance(Node, N - 1);
    {badrpc, nodedown} ->
      timer:sleep(300),
      start_zraft_application_on_instance(Node, N - 1);
    Message ->
      throw({'illegal message', Message})
  end.

start_zraft_application() ->
  {ok,zraft_util:start_app(zraft_lib)}.
