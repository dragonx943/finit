General Logging
===============

**Syntax:** `log { size = 200k  count = 5 }`

Log rotation for run/task/services that redirect output to a log file
with their own `log` block.  Global setting, applies to all services.

The size can be given as bytes, without a specifier, or in `k`, `M`,
or `G`, e.g. `size = 10M`, or `size = 3G`.  A value of `size = 0` disables
log rotation.  The default is `200k`.

The count value is recommended to be between 1-5, with a default 5.
Setting count to 0 means the logfile will be truncated when the MAX
size limit is reached.

Redirecting Output
------------------

The `run`, `task`, and `service` blocks take a `log` block of their own,
redirecting `stderr` and `stdout` of the application to a file or syslog
using the native `logit` tool.  This is useful for programs that do not
support syslog on their own, which is sometimes the case when running
in the foreground.

An empty block means syslog with the defaults, and three keys adjust it:

| Setting | Description |
|---|---|
| `file` | Write to this path instead of syslog |
| `priority` | Syslog `facility.level`, default `daemon.info` |
| `identity` | Syslog tag, default the basename of the command |

`/dev/console` and `/dev/null` are spelled as the paths they are:

    service foo { log { }                       command = "foo" }  # syslog
    service foo { log { file = "/var/log/foo" } command = "foo" }  # a file
    service foo { log { file = "/dev/console" } command = "foo" }  # console
    service foo { log { file = "/dev/null" }    command = "foo" }  # discard

> [!NOTE]
> A `log` block at file scope is a different setting -- that one is the
> global rotation above, and it takes only `size` and `count`.

Log rotation is controlled using the global `log` setting.

**Example:**

    service ntpd {
        description = "NTP daemon"
        log {
            priority = "user.warn"
            identity = "ntpd"
        }
        command = "/sbin/ntpd pool.ntp.org"
    }

Output Buffering
----------------

When using the `log` block, Finit redirects the service's stdout and
stderr to a pipe connected to a logger process.  Programs detect this as
non-interactive output (i.e., `isatty()` returns false) and typically
switch from line-buffered to fully-buffered mode.

Most well-behaved daemons explicitly flush their output or use syslog
directly, so this is rarely an issue.  However, if a service's log
messages appear delayed or batched, you can force line-buffered output
by wrapping the command with `stdbuf`:

    service myservice {
        description = "My service"
        log { }
        command = "/usr/bin/stdbuf -oL /path/to/command"
    }

The `-oL` option forces line-buffered output, and `-o0` forces unbuffered
output.  See `stdbuf(1)` for details.

> [!NOTE]
> Using `stdbuf` is rarely necessary. Only use it if you observe actual
> buffering issues with a specific service.
