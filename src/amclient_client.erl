-module(amclient_client).

-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {receiver}).
start(Name) ->
    amclient_sup:start_child(Name).

stop(Name) ->
    gen_server:call(Name, stop).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], [
        {hibernate_after, 500}
    ]).

init(_Args) ->
    self() ! init3,
    {ok, #state{}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(init, State) ->
    % dbg:tracer(),
    % dbg:p(all, c),
    % dbg:tpl(amqp10_client_session,cx),
    %% this will connect to a localhost node
    {ok, Hostname} = inet:gethostname(),
    User = <<"guest">>,
    Password = <<"guest">>,

    Port = 5672,
    %% create a configuration map
    OpnConf = #{
        address => Hostname,
        port => Port,
        container_id => <<"test-container">>,
        sasl => {plain, User, Password}
    },
    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),
    SenderLinkName = <<"test-sender">>,
    {ok, Sender} = amqp10_client:attach_sender_link(
        Session,
        SenderLinkName,
        <<"qq-2">>,
        undefined,
        configuration
    ),

    % wait for credit to be received
    wait_for_credit(Sender),

    % %% create a new message using a delivery-tag, body and indicate
    % %% it's settlement status (true meaning no disposition confirmation
    % %% will be sent by the receiver).
    OutMsg = amqp10_msg:new(<<"my-tag">>, <<"my-body">>, true),

    [
        begin
            case amqp10_client:send_msg(Sender, OutMsg) of
                ok -> ok;
                {error, insufficient_credit} -> wait_for_credit(Sender)
            end
        end
     || _ <- lists:seq(0, 55)
    ],

    ok = amqp10_client:detach_link(Sender),
    io:format("Send finished"),
    %% create a receiver link
    {ok, Receiver} = amqp10_client:attach_receiver_link(
        Session, <<"test-receiver">>, <<"classic-2">>
    ),

    %% grant some credit to the remote sender but don't auto-renew it
    ok = amqp10_client:flow_link_credit(Receiver, 500, never),

    {noreply, State#state{
        receiver = undefined
    }};
handle_info(init2, State) ->
    incoming_credit_accounting(),
    {noreply, State};
handle_info(init3, State) ->
    % create a configuration map
    OpnConf = #{
        address => "localhost",
        port => 5672,
        container_id => atom_to_binary(?FUNCTION_NAME, utf8),
        sasl => {plain, <<"guest">>, <<"guest">>}
    },

    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),
    SenderLinkName = <<"test-sender">>,

    QName = <<"hello">>,
    Address = <<"/amq/queue/", QName/binary>>,
    {ok, Sender} = amqp10_client:attach_sender_link(
        Session,
        SenderLinkName,
        Address,
        unsettled,
        configuration
    ),

    wait_for_credit(Sender),

   % [send_message(Sender, false, N) || N <- lists:seq(0, 15)],
    %wait_for_accepts(),
    flush("after drain"),

    ok = amqp10_client:detach_link(Sender),
    
    {ok, Msgs} = drain_queue(Session, Address),
    io:format("Msgs: ~p", [Msgs]),
    lists:foreach(fun(M) -> 
        io:format("~p~n", [M]) 
    end, Msgs),
    io:format("~nMsgs: ~p~n", [length(Msgs)]),
    case length(Msgs) of
        16 -> erlang:halt(0);
        _ -> erlang:halt(1)
    end,
    {noreply, State};

handle_info(recv, State) ->
    % create a configuration map
    OpnConf = #{
        address => "localhost",
        port => 5672,
        container_id => atom_to_binary(?FUNCTION_NAME, utf8),
        sasl => {plain, <<"guest">>, <<"guest">>}
    },

    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),
    SenderLinkName = <<"test-sender">>,

    QName = <<"test-queue">>,
    Address = <<"/amq/queue/", QName/binary>>,
    {ok, Msgs} = drain_queue(Session, Address),
    lists:map(fun(M) -> 
        io:format("Msg: ~p~n", [M])
        end, Msgs),
    io:format("~nMsgs: ~p~n", [length(Msgs)]),
    case length(Msgs) of
        16 -> erlang:halt(0);
        _ -> erlang:halt(1)
    end,
    {noreply, State};
handle_info({amqp10_msg, Receiver, InMsg}, State) ->
    io:format("."),
    io:format("A: ~p", [amqp10_client:accept_msg(Receiver, InMsg)]),
    %amqp10_client:flow_link_credit(Receiver, 1, never),
    {noreply, State};
handle_info({amqp10_event, {link, Receiver, credit_exhausted}}, State) ->
    amqp10_client:flow_link_credit(Receiver, 50, never),
    {noreply, State};
handle_info(_Info, State) ->
    io:format("Got message: ~p", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

wait_for_credit(Sender) ->
    io:format("Waiting for credit~n"),
    receive
        {amqp10_event, {link, Sender, credited}} ->
            io:format("Sender credited~n"),
            ok
    after 10000 ->
        exit(credited_timeout)
    end.

incoming_credit_accounting() ->
    SettleModes = [unsettled, mixed],
    EndpointDurabilities = [configuration, unsettled_state],
    Permutations = [{A, B} || A <- SettleModes, B <- EndpointDurabilities],
    lists:foreach(
        fun({EndpointSettleMode, EndpointDurability}) ->
            incoming_credit_accounting(
                5, on_publish, false, EndpointSettleMode, EndpointDurability
            ),
            incoming_credit_accounting(5, on_publish, true, EndpointSettleMode, EndpointDurability),
            incoming_credit_accounting(5, on_ack, false, EndpointSettleMode, EndpointDurability),
            incoming_credit_accounting(5, on_ack, true, EndpointSettleMode, EndpointDurability)
        end,
        Permutations
    ).
incoming_credit_accounting(
    _IncomingCredit, AckOn, MsgSettle, EdpointSettleMode, EndpointDurability
) ->
    io:format(
        "[incoming_credit_accounting] Endpoint settle mode: ~p Ack on: ~p , Msg settle: ~p"
        "Endpoint durability: ~p",
        [EdpointSettleMode, AckOn, MsgSettle, EndpointDurability]
    ),

    Port = 5672,
    QName = <<"test-queue">>,
    Address = <<"/amq/queue/", QName/binary>>,
    %% declare a quorum queue

    % create a configuration map
    OpnConf = #{
        address => "localhost",
        port => Port,
        container_id => atom_to_binary(?FUNCTION_NAME, utf8),
        sasl => {plain, <<"guest">>, <<"guest">>}
    },

    {ok, Connection} = amqp10_client:open_connection(OpnConf),
    {ok, Session} = amqp10_client:begin_session(Connection),
    SenderLinkName = <<"test-sender">>,
    {ok, Sender} = amqp10_client:attach_sender_link(
        Session,
        SenderLinkName,
        Address,
        EdpointSettleMode,
        EndpointDurability
    ),

    wait_for_credit(Sender),

    OutMsg = amqp10_msg:new(<<"my-tag">>, <<"my-body">>, MsgSettle),
    [
        begin
            io:format("Publish: ~p", [N]),
            case amqp10_client:send_msg(Sender, OutMsg) of
                ok -> ok;
                {error, insufficient_credit} -> wait_for_credit(Sender)
            end
        end
     || N <- lists:seq(0, 3)
    ],

    wait_for_credit(Sender),

    [
        case amqp10_client:send_msg(Sender, OutMsg) of
            ok -> ok;
            {error, insufficient_credit} -> wait_for_credit(Sender)
        end
     || _ <- lists:seq(0, 2)
    ],

    flush("final"),
    ok = amqp10_client:detach_link(Sender),

    ok = amqp10_client:close_connection(Connection),
    ok.

flush(N) ->
    io:format("Flushing: ~p", [N]),
    receive
        Msg ->
            io:format("Received: ~p", [Msg]),
            flush(N)
    after 100 ->
        ok
    end.

send_message(Sender, MsgSettle, N) ->
    Tag = crypto:strong_rand_bytes(12),
    OutMsg = amqp10_msg:new(Tag, erlang:integer_to_binary(N), MsgSettle),
    OutMsg2 = amqp10_msg:set_application_properties(#{
        "x-string" => "string-value",
        "atom" => atom_value,
        "x-int" => 3,
        "x-bool" => true,
        <<"x-binary">> => <<"binary-value">>
    }, OutMsg),
    OutMsg3 = amqp10_msg:set_properties(
        #{to => <<"test-to">>
    
    %    subject => <<"test-subject">>
    }
        , OutMsg2),
    perform_send_message(Sender, OutMsg3, N).

perform_send_message(Sender, OutMsg, N) -> 
    case amqp10_client:send_msg(Sender, OutMsg) of
        ok ->
            io:format("Publish OK ~p~n",[N]),
            ok;
        {error, insufficient_credit} ->
            io:format("Publish CREDIT ~p~n",[N]),
            wait_for_credit(Sender),
            perform_send_message(Sender, OutMsg, N)
    end.

wait_for_accepts() ->
    timer:sleep(10000).

drain_queue(Session, Address) -> 
    flush("Before after drain"),
    {ok, Receiver} = amqp10_client:attach_receiver_link(Session,
                    <<"test-receiver">>,
                    Address),

    ok = amqp10_client:flow_link_credit(Receiver, 1000, never, true),
    Msgs = receive_message(Receiver, []),
    flush("after drain"),
    ok = amqp10_client:detach_link(Receiver),
    {ok, Msgs}.

receive_message(Receiver, Acc) ->
    receive
        {amqp10_msg, Receiver, Msg} -> 
            receive_message(Receiver, [Msg | Acc])
    after 1000  ->
            lists:reverse(Acc)
    end.
