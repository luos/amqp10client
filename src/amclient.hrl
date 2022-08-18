
-define(LOG(Msg,Args), logger:info("[~s] ~p " ++ Msg, [?MODULE, self() | Args])).
