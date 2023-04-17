-module(amclient_config).

-export([
    hosts/0,
    number_of_messages/1,
    message_size/1,
    username/0,
    password/0,
    number_of_consumers/1,
    number_of_publishers/1,
    message_settlement_on_publish/1,
    endpoint_durability/0,
    output_file/0
]).

-spec hosts() -> [string()].
hosts() ->
    case os:getenv("RABBITMQ_HOSTS", undefined) of
        undefined ->
            [os:getenv("RABBITMQ_HOST", "localhost")];
        Uris ->
            string:split(Uris, ";", all)
    end.

username() -> erlang:list_to_binary(os:getenv("RABBITMQ_USERNAME", "guest")).
password() -> erlang:list_to_binary(os:getenv("RABBITMQ_PASSWORD", "guest")).

number_of_messages(Default) ->
    os_env_int("NUMBER_OF_MESSAGES", Default).

number_of_publishers(Default) ->
    os_env_int("NUMBER_OF_PUBLISHERS", Default).
number_of_consumers(Default) ->
    os_env_int("NUMBER_OF_CONSUMERS", Default).

message_size(Default) ->
    os_env_int("MESSAGE_SIZE", Default).

message_settlement_on_publish(Default) ->
    case os:getenv("MESSAGE_SETTLEMENT_ON_PUBLISH", undefined) of
        undefined -> Default;
        "settled" -> settled;
        "unsettled" -> unsettled;
        "mixed" -> mixed
    end.

endpoint_durability() ->
    case os:getenv("ENDPOINT_DURABILITY", undefined) of
        undefined -> case message_settlement_on_publish(unsettled) of
                        settled -> none;
                        unsettled -> configuration
                    end;
        "none" -> none;
        "configuration" -> configuration;
        "unspecified" -> unspecified
    end.

os_env_int(Name, Default) ->
    case os:getenv(Name, undefined) of
        undefined -> Default;
        Str -> list_to_integer(Str)
    end.

output_file() ->
    case os:getenv("AMCLIENT_OUT_FILE", undefined) of
        undefined -> "test.out";
        File -> File
    end.
