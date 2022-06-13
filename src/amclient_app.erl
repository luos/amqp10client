%%%-------------------------------------------------------------------
%% @doc amclient public API
%% @end
%%%-------------------------------------------------------------------

-module(amclient_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    application:ensure_all_started(amqp10_client),
    amclient_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
