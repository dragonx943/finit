This section provides an overview of Finit's configuration system. For
detailed information on specific topics, see the individual sections in
the navigation menu.


Configuration File Syntax
--------------------------

A `.conf` file is a series of blocks.  Every setting is a key inside
one, so nothing has to be remembered by position:

```aconf
service sysklogd {
    description = "System log daemon"
    runlevel    = "S123456789"
    envfile     = "-/etc/default/sysklogd"
    command     = "syslogd -F $SYSLOGD_ARGS"
}
```

Values are quoted strings, bare words, or integers.  Lists use braces,
and a block may carry a title, which becomes the service identity:

```aconf
# shell comment
// C++ comment
/* C comment */

key      = "value"                 # string
number   = 20                      # integer
flag     = true                    # boolean
list     = { "one", "two" }        # string list
block title { key = "value" }      # titled section

path = "${HOME}/thing"             # environment expansion
include("/etc/finit.d/extra.conf") # include another file
```

Bare words work wherever a string is expected, so `memory.max = 65M`
and `restart = always` need no quotes.

### Two conventions

Keys are kebab-case, never `snake_case` or `CamelCase`: `restart-sec`,
`stop-timeout`, `reboot-watchdog`.

Keys that take a list are plural: `conditions`, `conflicts`,
`capabilities`, `modules`, `extra-groups`.  Two imperatives keep their
singular form because they are verbs rather than nouns: `mknod` and
`include`.

### Short forms

Nine keys have an alias.  An alias may abbreviate the canonical name,
or preserve the spelling the line-based format used; it never renames.

| Canonical | Alias | Canonical | Alias |
|---|---|---|---|
| `description` | `desc` | `manual-start` | `manual` |
| `conditions` | `cond` | `remain-after-exit` | `remain` |
| `capabilities` | `caps` | `stop-signal` | `halt` |
| `modules` | `mod` | `stop-timeout` | `kill` |
| `envfile` | `env` | | |

### Optional paths

A leading `-` on a path means carry on if it is not there:

```aconf
service foo {
    envfile = "-/etc/default/foo"   # skip the file if missing
    command = "-/usr/sbin/foo"      # skip the whole block if missing
}
```

That is the only mark meaning "optional".  Two others mean something
else: `!` on `runlevel` inverts the set, e.g. `runlevel = "!12345"`,
and `~` on a condition propagates a reload from the service it names.
Both are covered where they apply.


Both Formats Are Read
---------------------

Finit also reads the line-based format it has always used, where a
stanza is a keyword followed by values whose meaning comes from their
position:

```aconf
service [S123456789] env:-/etc/default/sysklogd syslogd -F $SYSLOGD_ARGS -- System log daemon
```

That format still works and is not going away.  It is frozen at the
Finit 4.x feature set, so new settings appear only in the block format,
and the documentation is written in blocks throughout.  To convert a
file, see the [Syntax Migration Guide](migration.md).

There is no new file extension and no marker line.  Every file is still
`*.conf`, and Finit decides which format a file is in by reading it: if
it parses as blocks it is a block file, otherwise it goes to the
line-based parser.  A file is one format or the other, never a mix.

Because the two are told apart before either parser commits, a typo
reports its own file and line instead of being mistaken for the other
format:

```
parse error: /etc/finit.d/foo.conf:3: no such option 'commnad'
```

The .conf files `/etc/finit.conf` and `/etc/finit.d/*` support many
settings.  Some are restricted, e.g., only available at bootstrap,
runlevel `S`.  Read on in [Files & Layout](files.md) for more on how
to structure your .conf files.

For details on restrictions, see [Limitations](limitations.md).
