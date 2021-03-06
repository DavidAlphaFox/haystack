%% Copyright (c) 2012-2016 Peter Morgan <peter.james.morgan@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(haystack_app).
-behaviour(application).

-export([load/1]).
-export([start/2]).
-export([stop/1]).

start(_Type, _Args) ->
    try
        {ok, Sup} = haystack_sup:start_link(),
        [haystack:trace(true) || haystack_config:enabled(debug)],
        load("localhost.zone"),
        soa(haystack_config:origin()),
        {ok, Sup, #{listeners => [start_http(http),
                                  start_http(http_alt)]}}
    catch
        _:Reason ->
            {error, {Reason, erlang:get_stacktrace()}}
    end.

stop(#{listeners := Listeners}) ->
    lists:foreach(fun cowboy:stop_listener/1, Listeners);
stop(_State) ->
    ok.

load(Zone) ->
    dns_zone:process(haystack:priv_read_file(Zone)).

soa(Domain) ->
    dns_node:add(
      dns_name:labels(Domain),
      in,
      soa,
      655360,
      #{m_name => dns_name:labels(haystack_config:origin(ns)),
        r_name => dns_name:labels(haystack_config:origin(ns)),
        serial => 0,
        refresh => 0,
        retry => 0,
        expire => 0,
        minimum => 0}).


start_http(Prefix) ->
    {ok, _} = cowboy:start_http(Prefix,
                                haystack_config:acceptors(Prefix),
                                    [{port, haystack_config:port(Prefix)}],
                                    [{env, [dispatch(Prefix)]}]),
    Prefix.


dispatch(Prefix) ->
    {dispatch, cowboy_router:compile(resources(Prefix))}.


resources(http) ->
    [munchausen_proxy_resources(<<"_http._tcp.">>),
     dns_internal_resources(),
     api_resources()];

resources(http_alt) ->
    [munchausen_proxy_resources(<<"_http-alt._tcp.">>)].

munchausen_proxy_resources(Prefix) ->
    {<<"[...].", (haystack_config:origin(services))/binary>>,
     [{'_',
       munchausen_http_proxy_resource,
       #{prefix => Prefix,
         balancer => haystack_balance_random}}]}.

dns_internal_resources() ->
    {<<"localhost">>,
      [{<<"/zones">>, dns_zone_resource, []},
       {<<"/secrets">>, dns_secret_resource, []}]}.

api_resources() ->
    {'_',
     [{<<"/api/containers">>, haystack_api_containers_resource, []},
      {<<"/api/info">>, haystack_api_info_resource, []},
      {<<"/api/networks">>, haystack_api_networks_resource, []},
      {<<"/api/services">>, haystack_api_services_resource, []},
      {<<"/ui">>, haystack_permanently_moved_resource, #{path => <<"/ui/index.html">>}},
      {<<"/ui/services">>, haystack_permanently_moved_resource, #{path => <<"/ui/index.html">>}},
      {<<"/ui/networks">>, haystack_permanently_moved_resource, #{path => <<"/ui/index.html">>}},
      {<<"/ui/containers">>, haystack_permanently_moved_resource, #{path => <<"/ui/index.html">>}},
      {<<"/ui/[...]">>,
       munchausen_http_proxy_resource,
       #{balancer => fun
                         (_, <<"/ui/", Path/bytes>>) ->
                             #{host => "shortishly.github.io",
                               port => 80,
                               path => <<"/haystack-app/", Path/bytes>>}
                     end}}]}.
