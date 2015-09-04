# zraft_test

This repository contains a simple hacky test of zraft in a dynamic cluster setting.

Please copy (or link) a `rebar` binary to the local directory and run

```
./rebar get-deps
./run
```

to start an Erlang instance.  Then you should be able to run
`zraft_test:run(N, M)` to start the tests.  For example use
`zraft_test:run(4, 100)`.


Play with configuration parameters: change `dev.config`, e.g. reduce the log
size.
