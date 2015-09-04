-module(zraft_node).

%% API
-export([
  create/1,
  number/1,
  name/1,
  node/1,
  zraft_name/1
]).

-type zraft_node() :: {pos_integer(), atom(), node()}.
-export_type([zraft_node/0]).


%% ---------------------------------------------------------------------
%% API
%% ---------------------------------------------------------------------

-spec create(pos_integer()) -> zraft_node().
create(Number) ->
  {Number, name_of_number(Number), node_of_number(Number)}.

-spec number(zraft_node()) -> pos_integer().
number({Number, _, _}) -> Number.

-spec name(zraft_node()) -> atom().
name({_, Name, _}) -> Name.

-spec node(zraft_node()) -> node().
node({_, _, Node}) -> Node.

-spec zraft_name(zraft_node()) -> {zraft, node()}.
zraft_name({_, _, Node}) -> {zraft, Node}.


%% ---------------------------------------------------------------------
%% Internal functions
%% ---------------------------------------------------------------------

name_of_number(Number) ->
  list_to_atom("zraftnode" ++ integer_to_list(Number)).

node_of_number(Number) ->
  list_to_atom(atom_to_list(name_of_number(Number)) ++ "@localhost").
