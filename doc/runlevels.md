Runlevel Support
================

Basic support for [runlevels][5] is included in Finit from v1.8.  By
default all services, tasks, run commands and TTYs listed without a set
of runlevels get a default set `[234]` assigned.  The default runlevel
after boot is 2.

Finit supports runlevels 0-9, and S, with 0 reserved for halt, 6 reboot
and S for services that only run at bootstrap.  Runlevel 1 is the single
user level, where usually no networking is enabled.  In Finit this is
more of a policy for the user to define.  Normally only runlevels 1-6
are used, and even more commonly, only the default runlevel is used.

To specify an allowed set of runlevels for a `service`, `run` command,
`task`, or `tty`, set `runlevel` in your `/etc/finit.conf`, like this:

```
service syslogd {
    description = "System log daemon"
    runlevel    = "S12345"
    command     = "syslogd -n -x"
}
run acpid {
    description = "Starting ACPI Daemon"
    runlevel    = "S"
    command     = "/etc/init.d/acpid start"
}
task kbd {
    description = "Preparing console"
    runlevel    = "S"
    command     = "/etc/init.d/kbd start"
}
service klogd {
    description = "Kernel log daemon"
    runlevel    = "S12345"
    conditions  = { "pid/syslogd" }
    command     = "klogd -n -x"
}

tty tty1 { runlevel = "12345"  device = "/dev/tty1" }
tty tty2 { runlevel = "2"      device = "/dev/tty2" }
tty tty3 { runlevel = "2"      device = "/dev/tty3" }
tty tty4 { runlevel = "2"      device = "/dev/tty4" }
tty tty5 { runlevel = "2"      device = "/dev/tty5" }
tty tty6 { runlevel = "2"      device = "/dev/tty6" }
```

In this example syslogd is first started, in parallel, and then acpid is
called using a conventional SysV init script.  It is called with the run
command, meaning the following task command to start the kbd script is
not called until the acpid init script has fully completed.  Then the
keyboard setup script is called in parallel with klogd as a monitored
service.

Again, tasks and services are started in parallel, while run commands
are called in the order listed and subsequent commands are not started
until a run command has completed.  Also, task and run commands are run
in a shell, so pipes and redirects can be used.

The following examples illustrate this.  Bootstrap task and run commands
are also removed when they have completed, `initctl show` will not list
them.

```
task foo {
    runlevel = "S"
    command  = "echo \"foo\" | cat >/tmp/bar"
}
run secret {
    runlevel = "S"
    command  = "echo \"$HOME\" >/tmp/secret"
}
```

Switching between runlevels can be done by calling init with a single
argument, e.g. <kbd>init 5</kbd>, or using `initctl runlevel 5`, both
switch to runlevel 5.  When changing runlevels Finit also automatically
reloads all `.conf` files in the `/etc/finit.d/` directory.  So if you
want to set a new system config, switch to runlevel 1, change all config
files in the system, and touch all `.conf` files in `/etc/finit.d`
before switching back to the previous runlevel again — that way Finit
can both stop old services and start any new ones for you, without
rebooting the system.


[5]: https://en.wikipedia.org/wiki/Runlevel
