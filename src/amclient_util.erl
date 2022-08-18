-module(amclient_util).

-export([one_of/1, random_id/0]).

one_of(List) ->
    lists:nth(rand:uniform(length(List)), List).

random_id() ->
    base64:encode(crypto:strong_rand_bytes(12)).
