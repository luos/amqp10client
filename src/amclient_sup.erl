%%%-------------------------------------------------------------------
%% @doc amclient top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(amclient_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [
        #{
            id => amclient_client,
            start => {amclient_client_sup, start_link, []},
            type => supervisor
        },
        #{
            id => amclient_run_coordinator,
            start => {amclient_run_coordinator, start_link, [amclient_run_coordinator]},
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
