Service Options
===============

The `run`, `task`, `tty`, `service` and `sysv` blocks take settings as
keys.  This section lists them with their limitations.

The name of a service, shown by the `initctl` tool, is the block title.
It defaults to the basename of the executable if the title is omitted:

    service sshd {
        command = "/usr/sbin/sshd -D"
    }

For multiple instances of a service, with the same name, add an
identifier after a colon to prevent Finit from replacing previous
instances:

    service ssdp:eth1 { command = "ssdpd eth1" }
    service ssdp:eth2 { command = "ssdpd eth2" }

The [`initctl`](../initctl.md) tool will list these two services as:

 - ssdp:eth1
 - ssdp:eth2

Conflicting services that must be prevented from starting, use the
`conflicts` key:

    service udevd { command = "udevd" }
    run mdev {
        runlevel  = "S"
        conflicts = { "udevd" }
        command   = "mdev -s"
    }

The list may name several, and an instance is named the same way it is
declared:

    service abc:1 { command = "abc 1" }
    service abc:2 { command = "abc 2" }
    service cde   { conflicts = { "abc:1", "abc:2" }  command = "cde" }

If a service should not be automatically started, set `manual-start`.
It can then be started at any time with `initctl start <service>`:

    service lldpd {
        manual-start = true
        command      = "/usr/sbin/lldpd -d"
    }

Other run/task/service settings are:

  * `capabilities` -- see the [Linux Capabilities](capabilities.md) section
  * `cgroup NAME {}` -- see the [Cgroups](cgroups.md) section
  * `envfile` -- see the [Service Environment](service-env.md) section
  * `log {}` -- see [Redirecting Output](logging.md#redirecting-output)
  * `tty` -- see [Controlling TTY](tty.md#controlling-tty)
  * `notify` -- see [Service Synchronization](service-sync.md)
  * `if` -- see [Conditional Execution](services.md#conditional-execution)
  * `type = "forking"` -- see description of the [service](services.md) block
  * a leading `-` on `command` -- see
    [Conditional Loading](services.md#conditional-loading)

Restarting
----------

Services are automatically started, restarted, and stopped, depending
on the configuration and conditions.  Within the confines of that the
following settings are available:

  * `restart-max = NUM` -- number of times Finit tries to restart a
    crashing service, default: 10.  When this limit is reached the
    service is marked *crashed* and must be restarted manually with
    `initctl restart NAME`
  * `restart-sec = SEC` -- number of seconds before Finit tries to
    restart a crashing service.  The default is 2 seconds for the first
    half of `restart-max` attempts, then a back-off to 5 seconds -- with
    the default `restart-max` that is the first five retries.  The
    greater of this configured value and the back-off is used
  * `restart = "always"` -- no upper limit on the number of times Finit
    tries to restart a crashing service
  * `restart = "never"` -- do not restart on failures.  `false` is
    accepted as a synonym, and `true` selects the default policy
  * `respawn = true` -- bypasses the `restart` mechanism completely,
    allowing endless restarts.  Exiting is treated as normal work
    rather than failure, so the service is restarted at once instead of
    being counted and delayed.  This is how a `tty` behaves; it is not
    what `service` was designed for, so it is not the default
  * `remain-after-exit = true` -- for `run` and `task` only.  Prevents
    the task from re-running on runlevel re-entry and ensures the
    `exec-stop-post` script runs when the task is explicitly stopped or
    leaves its valid runlevels.  This is systemd's `RemainAfterExit=`.
    See [Task and Run](task-and-run.md) for more details
  * `oncrash = "reboot"` -- when all retries have failed, and the
    service has *crashed*, the system is rebooted
  * `oncrash = "script"` -- similarly, but instead of rebooting, call
    the `exec-stop-post` script with exit code `crashed`, see below

Service directories
-------------------

Five settings ask Finit to create a directory for the service before it
starts, owned by its `user` and `group`, mode 0755.  The value is a
directory name, resolved under a fixed base -- absolute paths and `..`
are refused:

| Setting | Base | Environment variable |
|---|---|---|
| `runtime-dir` | `/run` | `RUNTIME_DIRECTORY` |
| `state-dir` | `/var/lib` | `STATE_DIRECTORY` |
| `cache-dir` | `/var/cache` | `CACHE_DIRECTORY` |
| `logs-dir` | `/var/log` | `LOGS_DIRECTORY` |
| `config-dir` | `/etc` | `CONFIGURATION_DIRECTORY` |

Each resolved path is exported to the process environment under the
listed name, the same names systemd uses for `RuntimeDirectory=` and
friends.

The runtime directory is removed again when the service stops, after
any `exec-stop-post` script has run; `/run` is a tmpfs so it would not
survive a reboot anyway.  The other four persist.  A completed `run` or
`task` counts as stopped, unless `remain-after-exit` keeps it alive
until stopped for real.

This is what lets a service drop privileges and still create, and
later touch, its own PID file:

    service ntpd {
        user        = "ntp"
        group       = "ntp"
        runtime-dir = "ntpd"
        pidfile     = "/run/ntpd/ntpd.pid"
        command     = "/usr/sbin/ntpd -n -p /run/ntpd/ntpd.pid"
    }

These settings exist only in the block format.

Stopping and reloading
----------------------

When stopping a service, either manually or when moving to another
runlevel, Finit starts by sending `SIGTERM` to let the process shut
down gracefully.  If it has not been collected within 3 seconds,
`SIGKILL` follows.  Both ends of that are configurable:

  * `stop-signal = "SIGPWR"` -- send this instead of `SIGTERM`
  * `stop-timeout = 10` -- seconds to wait before `SIGKILL`, 1-300

Some services need more than a signal:

  * `exec-stop = "script [args]"` -- run instead of sending the stop
    signal, and instead of `stop` for `sysv`
  * `exec-reload = "script [args]"` -- run instead of sending `SIGHUP`.
    Like systemd, Finit sets `$MAINPID` as a convenience to scripts,
    which in effect also allows `exec-reload = "kill -HUP $MAINPID"`

If a daemon cannot be reloaded with a signal at all, say so and Finit
restarts it instead:

    service dropbear {
        reload-signal = "none"
        command       = "/usr/sbin/dropbear -R -F"
    }

`SIGHUP` is the default and the only other accepted value, with or
without the `SIG` prefix and in any case.

Scripts
-------

Services, including the `sysv` variant, support six lifecycle scripts:

  * `exec-start-pre` -- called before the sysv/service is started
  * `exec-start-ready` -- called when the sysv/service is ready
  * `exec-stop` -- called instead of the stop signal
  * `exec-stop-post` -- called after the sysv/service has stopped
  * `exec-reload` -- called instead of `SIGHUP`
  * `exec-cleanup` -- called when run/task/sysv/service is removed

Each takes a matching `-timeout`, in seconds, 0-3600, after which Finit
kills the script.  It defaults to the `stop-timeout` value and can be
disabled by setting it to zero:

    service foo {
        exec-start-pre         = "/etc/foo/pre.sh"
        exec-start-pre-timeout = 10
        command                = "/usr/sbin/foo"
    }

These scripts run as the same user and group as the service itself,
with any `envfile` sourced.  They are executed from the `$HOME` of the
given user.  The scripts are not called with any argument, but get a
set of environment variables:

  * `SERVICE_IDENT=foo:1`
  * `SERVICE_NAME=foo`
  * `SERVICE_ID=1`

The `exec-stop-post` script is called with an additional set of
environment variables.  Yes, the text is correct, the naming was an
accident:

 - `EXIT_CODE=[exited,signal,crashed]`: normal exit, signaled, or
   crashed
 - `EXIT_STATUS=[num,SIGNAME]`: set to one of exit status code from
   the program, if it exited normally, or the signal name (`HUP`,
   `TERM`, etc.) if it exited due to signal

When a run/task/sysv/service is removed (disable + reload) it is first
stopped and then removed from the runlevel.  The `exec-stop-post`
script always runs when the process has stopped, and `exec-cleanup`
runs when the block has been removed from the runlevel.

> [!IMPORTANT]
> These script actions are intended for setup, cleanup, and readiness
> notification.  A script that outlives its timeout is killed, so pick
> one that suits the work, or set it to zero to opt out and take
> responsibility for the script terminating.
