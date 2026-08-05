Services
========

**Syntax:** `service NAME { command = "/path/to/daemon ARGS" }`

Service, or daemon, to be monitored and automatically restarted if it
exits prematurely.  Finit tries to restart services that die, by default
10 times before giving up and marking them as *crashed*.  After which
they have to be manually restarted with `initctl restart NAME`.  The
limits controlling this are configurable, see
[Service Options](service-opts.md).

> [!TIP]
> To allow endless restarts, see [`respawn`](service-opts.md#restarting)
  
For daemons that support it, we recommend appending `--foreground`,
`--no-background`, `-n`, `-F`, or similar command line argument to
prevent them from forking off a sub-process in the background.  This is
the most reliable way to monitor a service.

However, not all daemons support running in the foreground, or they may
start logging to the foreground as well, these are forking daemons and
are supported using the same syntax as forking `sysv` services, by
naming the file to watch with `pidfile`.  There is an alternative that
may be more intuitive, where Finit can also guess the PID file based on
the daemon's command name:

    service ntpd {
        description = "NTP daemon"
        type        = "forking"
        command     = "ntpd"
    }

This example lets BusyBox `ntpd` daemonize itself.  Finit uses the
basename of the binary to guess the PID file to watch for the PID:
`/var/run/ntpd.pid`.  If Finit guesses wrong, name the file yourself
with `pidfile = "/path/to/file.pid"`.

The file belongs to the service: Finit reads it but does not create or
remove it.  That is the default, and `pidfile-create = true` is what
asks Finit to write the file instead.  The one exception is *stale*
cleanup — if the service dies without removing its own pidfile
(SIGKILL, OOM, segfault), and the file still names the just-reaped
PID, Finit removes it before the next retry.  This prevents daemons
that refuse to start on an existing pidfile (e.g. `dbus-daemon`)
from getting stuck in a crash-restart loop.

**Example:**

In the case of `ospfd` (below), we omit the `-d` flag (daemonize) to
prevent it from forking to the background:

    service ospfd {
        description = "OSPF daemon"
        runlevel    = "2345"
        conditions  = { "pid/zebra" }
        command     = "/sbin/ospfd"
    }

`runlevel` denotes the runlevels `ospfd` is allowed to run in, it is
optional and defaults to level 2-4 if omitted.

`conditions` lists what must be asserted before starting `ospfd`.  In
this example Finit waits for another service, `zebra`, to have created
its PID file in `/var/run/quagga/zebra.pid`.  Finit watches *all* files
in `/var/run`, for each file named `*.pid`, or `*/pid`, Finit opens it
and finds the matching `NAME:ID` using the PID.

A condition may be prefixed with `~` to propagate a reload of the
upstream service to this one, rather than merely pausing and resuming
it:

    conditions = { "~pid/zebra" }

If `ospfd` cannot be reloaded with `SIGHUP` at all, that is a property
of `ospfd` and not of the condition, so it is said directly:

    reload-signal = "none"

The legacy format spells that second one as a `!` leading the condition
list, which is not accepted here.  For details, see the
[Finit Conditions](../conditions.md) document.

Some services do not maintain a PID file and rather than patching each
application Finit provides a workaround.  With `pidfile-create` Finit
creates the file when starting and removes it when stopping.  The path
comes from `pidfile`, which takes three forms:

    pidfile = true              # /var/run/<command basename>.pid
    pidfile = "bar"             # a bare name, /var/run/bar.pid
    pidfile = "/run/bar.pid"    # an explicit path

Such a file is also used by the Finit condition subsystem, so another
service, run or task can depend on `pid/bar`.  Here foo is not started
until bar has:

    service bar {
        description    = "Bar Service"
        pidfile        = "/run/bar.pid"
        pidfile-create = true
        command        = "bar"
    }

    service foo {
        description = "Foo Service"
        conditions  = { "pid/bar" }
        command     = "foo"
    }

Needless to say, it is better if `bar` creates its own PID file when it
has completed starting up and is ready for service.

As an alternative "readiness" notification, Finit supports both systemd
and s6 style notification.  This is enabled with the `notify` key:

  * `notify = "systemd"` -- tells Finit the service uses the `sd_notify()`
    API to signal PID 1 when it has completed its startup and is ready
    to service events.  The [sd_notify()][] API expects `NOTIFY_SOCKET`
    to be set to the socket where the application can send `"READY=1\n"`
    when it is starting up or has processed a `SIGHUP`.
  * `notify = "s6"` -- puts Finit in s6 compatibility mode.  Compared to the
    systemd notification, [s6 expect][] compliant daemons to send `"\n"`
    and then close their socket.  Finit takes care of "hard-wiring" the
    READY state as long as the application is running, events across any
    `SIGHUP`.  Since s6 can give its applications the descriptor number
    (must be >3) on then command line, Finit provides the following
    syntax (`%n` is replaced by Finit with then descriptor number):

        service mdevd {
            runlevel = "S12345789"
            notify   = "s6"
            command  = "mdevd -O 4 -D %n"
        }

[sd_notify()]: https://www.freedesktop.org/software/systemd/man/sd_notify.html
[s6 expect]:   https://skarnet.org/software/s6/notifywhenup.html

When a service is ready, either by Finit detecting its PID file, or
their respective readiness mechanism has been triggered, Finit creates
then service's ready condition which other services can depend on:

    $ initctl -v cond get service/mdevd/ready
    on

This can be used to synchronize the start of another run/task/service:

    task mdevd-coldplug {
        runlevel   = "S"
        conditions = { "service/mdevd/ready" }
        user       = "root"
        group      = "root"
        command    = "mdevd-coldplug"
    }

Finit waits for `mdevd` to notify it, before starting `mdevd-coldplug`.
Notice how both start in runlevel S, and the coldplug task only runs in
S.  When the system moves to runlevel 2 (the default), coldplug is no
longer part of the running configuration (`initctl show`), this is to
ensure that coldplug is not called more than once.

>  For a detailed description of conditions, and how to debug them,
>  see the [Finit Conditions](../conditions.md) document.


Non-privileged Services
-----------------------

Every `run`, `task`, or `service` can also list the privileges the
command should be executed with, using `user`, `group` and
`extra-groups`, all optional:

    run hello {
        runlevel = "2345"
        user     = "joe"
        group    = "users"
        command  = "logger \"Hello world\""
    }

Finit reads the user's supplementary group membership from `/etc/group`
automatically.  Any groups the user belongs to will be inherited by
the service.

To specify additional supplementary groups beyond those in
`/etc/group`, list them in `extra-groups`:

    service caddy {
        user         = "caddy"
        group        = "caddy"
        extra-groups = { "ssl-cert" }
        command      = "/usr/bin/caddy run"
    }

This runs the `caddy` service as user `caddy`, with primary group
`caddy`, inheriting any groups `caddy` is a member of in `/etc/group`,
plus the additional `ssl-cert` group.  This is useful when a service
needs access to resources owned by groups not listed in `/etc/group`.

For multiple instances of the same command, e.g. a DHCP client or
multiple web servers, add `:ID` to the block title, like this:

    service httpd:80 {
        description = "Web server"
        runlevel    = "2345"
        command     = "httpd -f -h /http -p 80"
    }

    service httpd:8080 {
        description = "Old web server"
        runlevel    = "2345"
        command     = "httpd -f -h /http -p 8080"
    }

Without the `:ID` the latter will overwrite the former and only the old
web server would be started and supervised.

> [!NOTE]
> The line-based format also accepts a bare ID, `service :80 ...`,
> deriving the name from the command.  There is no block equivalent:
> the title carries both name and ID.


Conditional Loading
-------------------

Finit supports conditional loading of blocks.  The following example is
taken from the `system/10-hotplug.conf` file in the Finit distribution.
Here we only show a simplified subset.

Starting with the udev daemon, which goes by two names depending on
how it was built.  Both are candidates for the same service:

    service udevd {
        pidfile = "udevd"
        command = { "/lib/systemd/systemd-udevd", "-udevd" }
    }

When loading the .conf file Finit looks for
`/lib/systemd/systemd-udevd`, and if that is not there it moves on to
`udevd`.  A candidate that is not installed is expected, so no warning
is logged for the ones that are skipped.  The leading `-` on the last
one says it is also fine if none of them are found, in which case the
block is dropped quietly and no service named `udevd` exists.

> [!NOTE]
> This needs to be one block.  The title is the service identity, so
> two blocks titled `udevd` in the same file are two declarations of
> one service, which Finit rejects.  See [Duplicate
> titles](service-opts.md#duplicate-titles).

    run udevadm:1 {
        runlevel   = "S"
        if         = "udevd"
        conditions = { "pid/udevd" }
        command    = "-udevadm settle -t 0"
    }

This block is only loaded if we know of a service named `udevd`.  Again,
we do not warn if `udevadm` is not found, execution will also stop here
until the PID condition is asserted, i.e., Finit detecting udevd has
started.

    run mdev {
        description = "Populating device tree"
        runlevel    = "S"
        conflicts   = { "udevd" }
        command     = "-mdev -s"
    }

If `udevd` is not available, we try to run `mdev`, but if that is not
found, again we do not warn.

Conditional loading can also be negated, so the previous block can be
written as:

    run mdev {
        description = "Populating device tree"
        runlevel    = "S"
        if          = "!udevd"
        command     = "-mdev -s"
    }

The reason for using `conflicts` in this example is that a conflict can
be resolved.  Blocks naming a conflict are rechecked at runtime.


Conditional Execution
---------------------

Similar to conditional loading of blocks there is conditional runtime
execution.  This can be confusing at first, since Finit already has a
condition subsystem, but this is more akin to the qualification to a
runlevel.  E.g., a task with `runlevel = "123"` is qualified to run
only in runlevel 1, 2, and 3.  It is not considered for other
runlevels.

Conditional execution qualify a run/task/service based on a condition.
Consider this (simplified) example from the Infix operating system:

    run startup {
        runlevel   = "S"
        conditions = { "pid/sysrepo" }
        command    = "confd -b --load startup-config"
    }

    run failure {
        runlevel   = "S"
        if         = "usr/fail-startup"
        conditions = { "pid/sysrepo" }
        command    = "confd --load failure-config"
    }

The two run blocks reside in the same .conf file so Finit runs them in
true sequence.  If loading the file `startup-config` fails confd sets
the condition `usr/fail-startup`, thus allowing the next one to load
`failure-config`.

Notice the critical difference between the `conditions` list and `if`.
The former is a condition for starting; the latter is a condition to
check whether a run/task/service is qualified to even be considered.
`if` has a negation of its own, `!`, which is unrelated to anything in
the `conditions` list.

What `if` compares against depends on the value.  A namespace
separator makes it a condition, anything else is a service name:

| `if` | Asks |
|---|---|
| `"udevd"` | is a service by this name known? |
| `"usr/foo"` | was this condition set? |

Both are questions about whether the block belongs in the running
configuration at all, usually answered from what bootstrap established.
A statement is all of one kind or the other, so the block is rejected
if you mix them.

> [!NOTE]
> `if` qualifies, it does not track.  A condition asserted or cleared
> later does not start or stop the service by itself -- that is what
> the `conditions` list is for.

Conditional execution can also be negated, so provided the file loaded
did the opposite, i.e., set a condition on success, the previous block
can be written as:

    run failure {
        runlevel   = "S"
        if         = "!usr/startup-ok"
        conditions = { "pid/sysrepo" }
        command    = "confd ..."
    }

Variants of one service are often qualified this way, one per platform,
and they usually have to supply the same barrier to whatever waits for
them.  Each variant needs its own title, since a title is an identity,
and the shared barrier is named with `provides`.  See [Provided
Conditions](service-opts.md#provided-conditions).
