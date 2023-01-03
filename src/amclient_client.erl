-module(amclient_client).

-behaviour(gen_server).
-include("amclient.hrl").
%% API
-export([start/1, stop/1, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-record(state, {connection, session, run}).
-record(state_sender, {sender, number_of_messages, link_name}).
-record(state_receiver, {receiver, number_of_messages, link_name}).
start(N) ->
    amclient_client_sup:start_child(N).

stop(Name) ->
    gen_server:call(Name, stop).

start_link(N) ->
    gen_server:start_link(
        {local, list_to_atom(lists:flatten(io_lib:format("~s_~p", [?MODULE, N])))}, ?MODULE, [], [
            {hibernate_after, 500}
        ]
    ).

init(_Args) ->
    {ok, #state{}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(init_sender, State) ->
    % create a configuration map
    Host = amclient_util:one_of(amclient_config:hosts()),
    Port = 5672,
    NumberOfMessages = amclient_config:number_of_messages(100_000),

    SenderId = amclient_util:random_id(),
    LinkName = <<"test-sender-", SenderId/binary>>,

    OpnConf = #{
        address =>
            Host,
        port => Port,
        container_id => LinkName,
        sasl => {plain, amclient_config:username(), amclient_config:password()}
    },
    ?LOG("[~s] Connecting to '~s:~p'", [LinkName, Host, Port]),
    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),

    QName = <<"hello">>,
    Address = <<"/amq/queue/", QName/binary>>,
    {ok, Sender} = amqp10_client:attach_sender_link(
        Session,
        LinkName,
        Address,
        unsettled,
        configuration
    ),

    wait_for_credit(Sender),

    {noreply, State#state{
        connection = Connection,
        session = Session,
        run = #state_sender{
            sender = Sender,
            link_name = LinkName,
            number_of_messages = NumberOfMessages
        }
    }};
handle_info(init_receiver, State) ->
    % create a configuration map
    Host = amclient_util:one_of(amclient_config:hosts()),
    Port = 5672,
    NumberOfMessages = amclient_config:number_of_messages(100_000),

    SenderId = amclient_util:random_id(),
    LinkName = <<"test-receiver-", SenderId/binary>>,

    OpnConf = #{
        address =>
            Host,
        port => Port,
        container_id => LinkName,
        sasl => {plain, amclient_config:username(), amclient_config:password()},
        transfer_limit_margin => -10000
    },
    ?LOG("[~s] Connecting to '~s:~p'", [LinkName, Host, Port]),
    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),

    {noreply, State#state{
        connection = Connection,
        session = Session,
        run = #state_receiver{
            link_name = LinkName,
            number_of_messages = NumberOfMessages
        }
    }};
handle_info(
    run_sender,
    #state{
        run = #state_sender{
            sender = Sender,
            number_of_messages = NumberOfMessages,
            link_name = LinkName
        }
    } = State
) ->
    MessageSize = amclient_config:message_size(1),
    Message = crypto:strong_rand_bytes(MessageSize),
    ?LOG("[~p] Test started: ~p. Publishing ~p messages. ~n", [
        LinkName, calendar:system_time_to_rfc3339(erlang:system_time(second)), NumberOfMessages
    ]),
    {Elapsed, _} = timer:tc(fun() ->
        lists:foreach(
            fun(N) ->
                send_message(Sender, false, N, Message)
            end,
            lists:seq(0, NumberOfMessages - 1)
        ),
        wait_for_accepts(NumberOfMessages)
    end),
    ?LOG("Test ended: ~p~n", [calendar:system_time_to_rfc3339(erlang:system_time(second))]),
    MsgsPerSec = NumberOfMessages / (Elapsed / 1000 / 1000),
    ?LOG("Test ended, took: ~p milliseconds. ~p messages / second. ~n", [Elapsed / 1000, MsgsPerSec]),
    {noreply, State};
handle_info(
    run_receiver,
    #state{
        session = Session,
        run = #state_receiver{
            number_of_messages = NumberOfMessages,
            link_name = LinkName
        }
    } = State
) ->
    QName = <<"hello">>,
    Address = <<"/amq/queue/", QName/binary>>,
    {ok, Receiver} = amqp10_client:attach_receiver_link(
        Session,
        LinkName,
        Address,
        amclient_config:message_settlement_on_publish(unsettled),
        configuration
    ),
    
    
    ok = amqp10_client:flow_link_credit(Receiver, 100, 50, false),

    ?LOG("[~p] Test started: ~p. Receiving ~p messages. ~n", [
        LinkName, calendar:system_time_to_rfc3339(erlang:system_time(second)), NumberOfMessages
    ]),
    {Elapsed, Msgs} = timer:tc(fun() ->
        receive_message(Receiver, [], NumberOfMessages)
    end),
    ?LOG("Test ended: ~p~n", [calendar:system_time_to_rfc3339(erlang:system_time(second))]),
    ?LOG("Received ~p messages", [length(Msgs)]),
    MsgsPerSec = NumberOfMessages / (Elapsed / 1000 / 1000),
    ?LOG("Test ended, took: ~p milliseconds. ~p messages / second. ~n", [Elapsed / 1000, MsgsPerSec]),
    {noreply, State};
handle_info({amqp10_msg, Receiver, InMsg}, State) ->
    %io:format("."),
    %io:format("A: ~p", [amqp10_client:accept_msg(Receiver, InMsg)]),
    %amqp10_client:flow_link_credit(Receiver, 1, never),
    {noreply, State};
handle_info({amqp10_event, {link, Receiver, credit_exhausted}}, State) ->
    amqp10_client:flow_link_credit(Receiver, 50, never),
    {noreply, State};
handle_info(_Info, State) ->
    ?LOG("Got message: ~p", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

wait_for_credit(Sender) ->
    ?LOG("Waiting for credit~n", []),
    receive
        {amqp10_event, {link, Sender, credited}} ->
            ?LOG("Sender credited~n", []),
            ok
    after 60000 ->
        exit(credited_timeout)
    end.

flush(N) ->
    io:format("Flushing: ~p", [N]),
    receive
        Msg ->
            ?LOG("Received: ~p", [Msg]),
            flush(N)
    after 100 ->
        ok
    end.

send_message(Sender, MsgSettle, N, Content) ->
    Tag = crypto:strong_rand_bytes(12),
    Now = erlang:system_time(millisecond),
    OutMsg = amqp10_msg:new(Tag, <<Now:64, Content/binary>>, MsgSettle),
    OutMsg2 = amqp10_msg:set_application_properties(
        #{
            "x-message-seq" => N,
            "x-string" => "string-value",
            "atom" => atom_value,
            "x-int" => 3,
            "x-bool" => true,
            <<"x-binary">> => <<"binary-value">>
        },
        OutMsg
    ),
    OutMsg3 = amqp10_msg:set_properties(
        %    subject => <<"test-subject">>
        #{to => <<"test-to">>},
        OutMsg2
    ),
    perform_send_message(Sender, OutMsg3, N).

perform_send_message(Sender, OutMsg, N) ->
    case amqp10_client:send_msg(Sender, OutMsg) of
        ok ->
            %io:format("Publish OK ~p~n",[N]),
            ok;
        {error, insufficient_credit} ->
            ?LOG("Publish CREDIT ~p~n", [N]),
            wait_for_credit(Sender),
            perform_send_message(Sender, OutMsg, N)
    end.

wait_for_accepts(0) ->
    ok;
wait_for_accepts(N) ->
    receive
        {amqp10_disposition, {accepted, _}} -> wait_for_accepts(N - 1)
    after 10000 ->
        exit(io_lib:format("Accept not received: ~p", [N]))
    end.

drain_queue(Session, Address) ->
    flush("Before after drain"),
    {ok, Receiver} = amqp10_client:attach_receiver_link(
        Session,
        <<"test-receiver">>,
        Address
    ),

    ok = amqp10_client:flow_link_credit(Receiver, 1000, never, true),
    Msgs = receive_message(Receiver, []),
    flush("after drain"),
    ok = amqp10_client:detach_link(Receiver),
    {ok, Msgs}.

receive_message(Receiver, Acc) ->
    receive
        {amqp10_msg, Receiver, Msg} ->
            amqp10_client:accept_msg(Receiver, Msg),
            receive_message(Receiver, [Msg | Acc])
    after 10000 ->
        lists:reverse(Acc)
    end.

receive_message(_Receiver, Acc, 0) -> lists:reverse(Acc);
receive_message(Receiver, Acc, N) ->
    receive
        {amqp10_msg, Receiver, Msg} ->
            amqp10_client:accept_msg(Receiver, Msg),
            receive_message(Receiver, [Msg | Acc], N -1)
    after 30000 ->
        lists:reverse(Acc)
    end.
    