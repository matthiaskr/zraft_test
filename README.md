# zraft_test

This repository contains a simple hacky test of zraft in a dynamic cluster setting.

Please copy (or link) a `rebar` binary to the local directory and run

```
./rebar get-deps
./run
```

to run the test (driven by escript `./runtest`.  You may want to experiment
various parameters to `zraft_test:run/2` in `main/1` of the `./runtest`
script.

Play with configuration parameters: change `dev.config`, e.g. reduce the log
size.
