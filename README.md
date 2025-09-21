
# SQLite3 CLI

`sqlite3`, but with some improvements

## Description

This project originated due to some limitations of the original `sqlite3` shell tool which I've
encountered (or couldn't directly solve) whilst using it for a work project. Particularly, there is
no way of performing parameter binding through arguments or stdin. Quoting is quite difficult to do.
There will be some witty stuff added in the future.

```
$ zig build
$ zig-out/bin/sqlite3-cli --help

    SQLite3 CLI
    sqlite3-cli [option ...] file query

parameter bindings
    --bind string
    --bind-stdin

options
    --readonly
    --nocreate
    --nodefaults
    --notrim
    --doptions
    --help

```

Currently, only executes are supported (no retrievals yet). An example:

```
$ cat path/to/dump | sqlite3-cli \
    Cellar/service.sqlite \
    "INSERT INTO foo (id, data) VALUES (?, ?);" \
    --bind "$uuid" \
    --bind-stdin
```

SQLite3 doesn't really care about types, and as such, no type safety is performed.

### Maybe planned stuff

* `--pragma key value`
* `--timeout ms` - shortcut for `--pragma busy_timeout ms`
* `--sql file` - multiple sql commands

## Acknowledgements

Commit HEAD compiled with Zig `0.14.1`.

Lays on top of the stupefying interface by [`vrischmann/zig-sqlite`](https://github.com/vrischmann/zig-sqlite).

Related project: [`QSmally/SQLite3-Snapshot`](https://github.com/QSmally/SQLite3-Snapshot).
