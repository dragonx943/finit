Syntax Migration Guide
======================

Finit reads both configuration formats.  Every file is still `*.conf`,
and the format is detected per file, so a system can be migrated one
file at a time -- a file is one format or the other, never a mix.

This guide maps each part of a line-based stanza to its block key.

The shape of the change:

    service [S12345] <pid/syslogd> env:-/etc/default/klogd name:klogd klogd -n $KLOGD_OPTS -- Kernel log daemon

becomes

    service klogd {
        description = "Kernel log daemon"
        runlevel    = "S12345"
        conditions  = { "pid/syslogd" }
        envfile     = "-/etc/default/klogd"
        command     = "klogd -n $KLOGD_OPTS"
    }

The block title is the service identity, shown by `initctl`.  Multiple
instances spell the ID in the title: `service sshd:1 { ... }`.  The
legacy bare-ID form, `service :80 ...`, has no equivalent -- the title
carries both name and ID.

Positional parts
----------------

| Line-based                       | Block key                                             |
|----------------------------------|-------------------------------------------------------|
| `service`, `task`, `run`, `sysv` | same, as block type                                   |
| `[S12345]`                       | `runlevel = "S12345"`                                 |
| `<pid/a,net/b>`                  | `conditions = { "pid/a", "net/b" }`                   |
| `<!pid/a>` on service/sysv       | `conditions = { "pid/a" }` + `reload-signal = "none"` |
| `<!pid/a>` on run/task           | `conditions = { "pid/a" }` + `required = false`       |
| `@user:group,extra`              | `user`, `group`, `extra-groups = { "extra" }`         |
| `name:foo :1`                    | block title `foo:1`                                   |
| the command and arguments        | `command = "..."`                                     |
| `-- Description text`            | `description = "..."`                                 |

The `!` was a flag on the stanza, not a negation, and meant different
things for daemons and one-shots; each meaning is now its own key.  A
`~` prefix on a condition is unchanged: `conditions = { "~pid/a" }`.

Service options
---------------

| Line-based                       | Block key                                        |
|----------------------------------|--------------------------------------------------|
| `env:[-]/path`                   | `envfile = "[-]/path"`                           |
| `pid:/path`                      | `pidfile = "/path"` + `pidfile-create = true`    |
| `pid:!/path`                     | `pidfile = "/path"`                              |
| `pid`                            | `pidfile = true` + `pidfile-create = true`       |
| `log`                            | `log { }`                                        |
| `log:/path`                      | `log { file = "/path" }`                         |
| `log:null`, `log:console`        | `log { file = "/dev/null" }`, `"/dev/console"`   |
| `log:prio:p,tag:t`               | `log { priority = "p"  identity = "t" }`         |
| `notify:systemd`                 | `notify = "systemd"`                             |
| `type:forking`                   | `type = "forking"`                               |
| `manual:yes`                     | `manual-start = true`                            |
| `remain:yes`                     | `remain-after-exit = true`                       |
| `restart:always` / `restart:NUM` | `restart = "always"` / `restart-max = NUM`       |
| `restart_sec:SEC`                | `restart-sec = SEC`                              |
| `norestart`                      | `restart = "never"`                              |
| `respawn`                        | `respawn = true`                                 |
| `oncrash:reboot`                 | `oncrash = "reboot"`                             |
| `halt:SIG`                       | `stop-signal = "SIG"`                            |
| `kill:SEC`                       | `stop-timeout = SEC`                             |
| `pre:[TMO,]/script`              | `exec-start-pre`, `exec-start-pre-timeout`       |
| `ready:[TMO,]/script`            | `exec-start-ready`, and its `-timeout`           |
| `stop:[TMO,]/script`             | `exec-stop`, and its `-timeout`                  |
| `post:[TMO,]/script`             | `exec-stop-post`, and its `-timeout`             |
| `reload:[TMO,]/script`           | `exec-reload`, and its `-timeout`                |
| `cleanup:[TMO,]/script`          | `exec-cleanup`, and its `-timeout`               |
| `caps:^cap_a,%cap_b`             | `capabilities = { "^cap_a", "%cap_b" }`          |
| `conflict:a,b`                   | `conflicts = { "a", "b" }`                       |
| `if:svc` / `if:<cond>`           | `if = "svc"` / `if = "cond"`, no angle brackets  |
| `tty:/dev/x`                     | `tty = "/dev/x"`                                 |
| `nowarn`                         | leading `-` on `command` or `envfile`            |
| `restarttmo:`                    | dropped, was already an alias for `restart_sec:` |

Cgroups
-------

The standalone `cgroup.NAME` line selected a group for every stanza
after it in the file, and `cgroup:opts` applied settings to whichever
group was current.  Neither survives: every block names its own group,
so nothing depends on what came earlier in the file.

    cgroup.maint
    service [2345] cgroup:cpu.weight:250 foo -- Foo daemon

becomes

    service foo {
        description = "Foo daemon"
        runlevel    = "2345"
        cgroup maint { cpu.weight = 250 }
        command     = "foo"
    }

Top-level group declarations keep their name and settings:

    cgroup system cpu.weight:9700 mem.max:10M

becomes

    cgroup system {
        cpu.weight = 9700
        memory.max = 10M
    }

TTYs
----

The three positional variants become three key choices:

    tty [12345] /dev/ttyS0 115200 noclear vt220
    tty [12345] /sbin/getty -L ttyS0 115200 vt100
    tty [12345] notty

become

    tty ttyS0 {
        runlevel = "12345"
        device   = "/dev/ttyS0"
        baud     = 115200
        term     = "vt220"
        noclear  = true
    }
    tty getty {
        runlevel = "12345"
        command  = "/sbin/getty -L ttyS0 115200 vt100"
    }
    tty shell {
        runlevel = "12345"
        notty    = true
    }

Top-level directives
--------------------

| Line-based                       | Block key                                                |
|----------------------------------|----------------------------------------------------------|
| `host NAME`, `hostname NAME`     | `hostname = "NAME"`                                      |
| `module foo args` (repeated)     | `modules = { "foo args", ... }`                          |
| `network script args`            | `network = "script args"`                                |
| `runlevel N`                     | `runlevel = N`                                           |
| `rcsd /path`                     | `rcsd = "/path"`                                         |
| `runparts [progress] [sysv] DIR` | `runparts = "DIR"`, `runparts-progress`, `runparts-sysv` |
| `set KEY=VAL` (repeated)         | `environment { KEY = "VAL" }`                            |
| `log size:100k count:4`          | `log { size = 100k  count = 4 }`                         |
| `rlimit [hard\|soft] RES LIM`    | `rlimit { hard.res = LIM }`                              |
| `readiness none`                 | `readiness = "none"`                                     |
| `reboot-delay N`                 | `reboot-delay = N`                                       |
| `reboot-watchdog on`             | `reboot-watchdog = true`                                 |
| `service-interval SEC`           | `service-interval = SEC`                                 |
| `shutdown script`                | `shutdown = "script"`                                    |
| `mknod /dev/x c 1 2`             | `mknod = { "/dev/x c 1 2" }`                             |
| `include /path`                  | `include("/path")`                                       |

Worth knowing
-------------

  * Templates work unchanged: `%i` is replaced before the file is
    parsed, so `service serv:%i { ... }` in a `serv@.conf` behaves
    exactly like its legacy counterpart.
  * A list cannot hold comments; the lexer reads entries after a `#`
    regardless.  Put commented-out candidates above the list.
  * `$VAR` in a value is expanded when the file is read, against
    Finit's environment.  An unset variable expands to nothing.
  * New settings only appear in the block format.  The first are the
    [per-service directories](service-opts.md#service-directories),
    `runtime-dir` and friends.

For the full description of every key, see the rest of the
[Configuration](index.md) section.
