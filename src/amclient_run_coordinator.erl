-module(amclient_run_coordinator).
-include("amclient.hrl").
-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {
    senders = [],
    receivers = []
}).
start(Name) ->
    amqclient_sup:start_child(Name).

stop(Name) ->
    gen_server:call(Name, stop).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

init(_Args) ->
    ?LOG("Started.", []),
    self() ! init,
    {ok, #state{senders = [], receivers = []}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(init, State) ->
    NumSenders = amclient_config:number_of_publishers(1),
    NumReceivers = amclient_config:number_of_consumers(0),
    Senders = [
        begin
            {ok, P} = amclient_client:start(N),
            P ! init_sender,
            P
        end
     || N <- lists:seq(1, NumSenders)
    ],
    Receivers = [
        begin
            {ok, P} = amclient_client:start(N + NumSenders),
            P ! init_receiver,
            P
        end
     || N <- lists:seq(1, NumReceivers)
    ],
    timer:sleep(1000),
    ?LOG("Initialised ~p senders and ~p receivers.", [NumSenders, NumReceivers]),
    [
        begin
            R ! run_receiver
        end
     || R <- Receivers
    ],
    [
        begin
            R ! run_sender
        end
     || R <- Senders
    ],

    {noreply, State#state{
        receivers = Receivers,
        senders = Senders
    }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
