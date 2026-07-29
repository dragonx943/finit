SysV Init Compatibility
=======================

It is not possible to run unmodified SysV init systems with Finit.  This
was never the intention and is not the strength of Finit.  However, it
comes with a few SysV Init compatibility features to ease the transition
from a serialized boot process.

SysV Init Scripts
-----------------

**Syntax:** `sysv NAME { command = "/path/to/init-script" }`

> [!NOTE]
> Conditions, runlevels, and the other settings a `sysv` block takes
> are described in [Service Options](service-opts.md).

A `sysv` block is a supervised daemon, like `service`, but started and
stopped through a SysV style init script instead of a command line.  The
intention is to reuse existing setup and init scripts from Linux
distributions.
  
When entering an allowed runlevel, Finit calls `init-script start`, when
entering a disallowed runlevel, Finit calls `init-script stop`, and if
the Finit .conf, where the `sysv` block is declared, is modified, Finit
calls `init-script restart` on `initctl reload`.  Similar to how
`service` blocks work.

Forking services started with `sysv` scripts can be monitored by Finit
by declaring the PID file to look for: `pidfile = "/path/to/file.pid"`.
Finit does not create that file, it watches it for the resulting
forked-off PID.  That is the default; `pidfile-create = true` asks Finit
to write it instead.  The same applies to forking daemons with no way to
run in the foreground, see [Services](services.md).

> [!TIP]
> See also [SysV Init Compatibility](#sysv-init-compatibility).

Run-parts
---------

For a directory with traditional start/stop scripts that should run, in
order, at bootstrap, Finit provides the `runparts` setting.  It runs
in runlevel S, at the very end of it (before calling `/etc/rc.local`)
making it perfect for most scenarios.

For syntax details, see the [Run-parts Scripts](runparts.md) section.
Here is an example take from a Debian installation:

    runparts = "/etc/rc2.d"

Files in these directories are usually named `SNNfoo` and `KNNfoo`,
which Finit knows about and automatically appends the correct argument:

    /bin/sh -c /etc/rc2.d/S01openbsd-inetd start

or

    /bin/sh -c /etc/rc0.d/K01openbsd-inetd stop

Files that do not match this pattern are started similarly but without
the extra command line argument.

Start/Stop Scripts
------------------

For syntax details, see [SysV Init Scripts](#sysv-init-scripts), above.
Here follows an example taken from a Debian installation:

    sysv inetd {
        description = "OpenBSD inet daemon"
        runlevel    = "2345"
        conditions  = { "pid/syslogd" }
        command     = "/etc/init.d/openbsd-inetd"
    }

The init script header could be parsed to extract `Default-Start:` and
other parameters for the `sysv` command to Finit.  There is currently no
way to detail a generic syslogd dependency in Finit, so `Should-Start:`
in the header must be mapped to the condition system in Finit using an
absolute reference, here we depend on the sysklogd project's syslogd.

`/etc/rc.local`
---------------

One often requested feature, early on, was a way to run a site specific
script to set up, e.g., static routes or firewall rules.  A user can add
a `task` or `run` command in the Finit configuration for this, but for
compatibility reasons the more widely know `/etc/rc.local` is used if
it exists, and is executable.  It is called very late in the boot process
when the system has left runlevel S, stopped all old and started all new
services in the target runlevel (default 2).

> [!NOTE]
> In Finit releases before v4.5 this script blocked Finit execution and
> made it as good as impossible to call `initctl` during that time.

`init q`
--------

When `/sbin/finit` is installed as `/sbin/init`, it is possible to use
`init q` to reload the configuration.  This is the same as calling
`initctl reload`.
