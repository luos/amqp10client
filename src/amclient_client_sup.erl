%%%-------------------------------------------------------------------
%% @doc amclient top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(amclient_client_sup).

-behaviour(supervisor).

-export([start_link/0, start_child/1]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child(N) -> 
    supervisor:start_child(?MODULE, [N]).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [
        #{
            id => amclient_client,
            start => {amclient_client, start_link, []},
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
