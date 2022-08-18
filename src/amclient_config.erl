-module(amclient_config).

-export([
    hosts/0,
    number_of_messages/1,
    message_size/1,
    username/0,
    password/0,
    number_of_consumers/1,
    number_of_publishers/1
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

os_env_int(Name, Default) ->
    case os:getenv(Name, undefined) of
        undefined -> Default;
        Str -> list_to_integer(Str)
    end.