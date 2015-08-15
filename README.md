# Haystack

Haystack is a minimal
[DNS](https://en.wikipedia.org/wiki/Domain_Name_System) server written
in [Erlang](http://erlang.org).

## Building

Haystack uses [erlang.mk](https://github.com/ninenines/erlang.mk). To build run:

```
make
```

[![Build Status](https://travis-ci.org/shortishly/haystack.svg)](https://travis-ci.org/shortishly/haystack)

## Running

To run the release:

```
make run
```

## Quick start

We will use
[ddns-confgen](http://ftp.isc.org/isc/bind9/9.9.0rc1/bind-9.9.0rc1/bin/confgen/ddns-confgen.html)
and [nsupdate](https://en.wikipedia.org/wiki/Nsupdate) to update some
records in the `example.test` DNS domain.

We need to make Haystack an authority for the `example.test` domain by
manually adding a [SOA](https://en.wikipedia.org/wiki/List_of_DNS_record_types#SOA) record for the `example.test` domain.

```erlang
haystack_node:add([<<"example">>,<<"test">>],
    in,
    soa,
    100,
    #{m_name => [<<"ns">>, <<"example">>, <<"test">>],
      r_name => [<<"hostmaster">>, <<"example">>, <<"test">>],
      serial => 20,
      refresh => 7200,
      retry => 600,
      expire => 3600000,
      minimum => 60}).
```

We can verify that this SOA is now present in Haystack with a simple dig query:

```shell
dig @localhost -p 3535 example.test soa
```

We will create a new key that will be used to authorise the
updates on our registry:

```shell
ddns-confgen -q -a hmac-md5 -k key.example.test -s example.test>key.example.test
```

The above command creates a key that will be used by subsequent
updates to the registry. We will assume that the newly created key is
as follows:

> key "key.example.test" {<br />
>	algorithm hmac-md5;<br />
>	secret "BriKgwLS0+O8tRXI7au/fw==";<br />
>};<br />

Add this shared secret to the registry as follows:

```erlang
haystack_secret:add([<<"key">>, <<"example">>,<<"test">>],base64:decode("BriKgwLS0+O8tRXI7au/fw==")).
```

Using the same secret with `nsupdate` to update the registry:

```shell
nsupdate -l -p 3535 -k key.example.test
```
> update delete haystack.example.test A<br />
> update add haystack.example.test 86400 A 10.1.2.3<br />
> update add haystack.example.test 86400 A 10.1.2.4<br />
> update add haystack.example.test 86400 A 10.1.2.5<br />
> send<br />
> quit<br />

Verify the updates with:

```shell
dig @localhost -p 3535 haystack.example.test a
```
