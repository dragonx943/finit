Configuration Example
=====================

This example `/etc/finit.conf` can also be split up in multiple `.conf`
files in `/etc/finit.d`.  Available, but not yet enabled, services can
be placed in `/etc/finit.d/available` and enabled by an operator using
the [initctl](initctl.md) tool.

See the [contrib/][contrib] directory on GitHub for examples, or take a
peek at systems using Finit, like [Infix OS][infix] and [myLinux][].

> [!TIP]
> A block spans as many lines as it needs, so no continuation character is
> called for.  For the full syntax, see the [finit.conf(5)][] manual or the
> [Configuration](config/index.md) section.

```ApacheConf
# Fallback if /etc/hostname is missing
hostname = "default"

# Runlevel to start after bootstrap, 'S', default: 2
#runlevel = 2

# Global environment variables, be careful though with variables like
# PATH, SHELL, LOGNAME, etc.
#environment {
#    PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
#}

# Max file size for each log file: 100 kiB, rotate max 4 copies:
# log => log.1 => log.2.gz => log.3.gz => log.4.gz
log {
    size  = 100k
    count = 4
}

# Services to be monitored and respawned as needed
service watchdog {
    description = "System watchdog daemon"
    runlevel    = "S12345"
    envfile     = "-/etc/conf.d/watchdog"
    command     = "watchdog $WATCHDOG_OPTS $WATCHDOG_DEV"
}
service syslogd {
    description = "System log daemon"
    runlevel    = "S12345"
    envfile     = "-/etc/conf.d/syslog"
    command     = "syslogd -n $SYSLOGD_OPTS"
}
service klogd {
    description = "Kernel log daemon"
    runlevel    = "S12345"
    conditions  = { "pid/syslogd" }
    envfile     = "-/etc/conf.d/klogd"
    command     = "klogd -n $KLOGD_OPTS"
}
service lldpd {
    description = "LLDP daemon (IEEE 802.1ab)"
    runlevel    = "2345"
    envfile     = "-/etc/conf.d/lldpd"
    command     = "lldpd -d $LLDPD_OPTS"
}

# The BusyBox ntpd does not use syslog when running in the foreground
# So we use this trick to redirect stdout/stderr to a log file.  The
# log file is rotated with the above settings.  The condition declares
# a dependency on a system default route (gateway) to be set.  ntpd
# does not respect SIGHUP, so Finit restarts it on reload instead.
service ntpd {
    description   = "NTP daemon"
    runlevel      = "2345"
    conditions    = { "net/route/default" }
    reload-signal = "none"
    log { file = "/var/log/ntpd.log" }
    command       = "ntpd -n -l -I eth0"
}

# For multiple instances of the same service, add :ID to the block title.
service merecat:80 {
    description = "Web server"
    runlevel    = "2345"
    command     = "merecat -n -p 80 /var/www"
}
service merecat:8080 {
    description = "Old web server"
    runlevel    = "2345"
    command     = "merecat -n -p 8080 /var/www"
}

# Alternative method instead of below runparts, can also use /etc/rc.local
#sysv keyboard-setup {
#    description = "Setting up preliminary keymap"
#    runlevel    = "S"
#    command     = "/etc/init.d/keyboard-setup"
#}

# Hidden from boot progress, using an empty description
#sysv acpid {
#    description = ""
#    runlevel    = "S"
#    command     = "/etc/init.d/acpid"
#}

# Run start scripts from this directory
#runparts = "/etc/start.d"

# Virtual consoles run BusyBox getty, keep kernel default speed
tty tty1 {
    runlevel = "12345"
    command  = "/sbin/getty -L 0 /dev/tty1 linux"
    nowait   = true
    noclear  = true
}
tty tty2 {
    runlevel = "2345"
    command  = "/sbin/getty -L 0 /dev/tty2 linux"
    nowait   = true
    noclear  = true
}
tty tty3 {
    runlevel = "2345"
    command  = "/sbin/getty -L 0 /dev/tty3 linux"
    nowait   = true
    noclear  = true
}

# Use built-in getty for serial port and USB serial
#tty ttyAMA0 { runlevel = "12345"  device = "/dev/ttyAMA0"  noclear = true  nowait = true }
#tty ttyUSB0 { runlevel = "12345"  device = "/dev/ttyUSB0"  noclear = true }

# Just give me a shell, I need to debug this embedded system!
#tty console { runlevel = "12345"  device = "@console"  noclear = true  nologin = true }
```

The `service` stanza, as well as `task`, `run` and others are described in
full in the [Services Syntax](config/services.md) section.

Here's a quick overview of some of the most common components needed to start
a UNIX daemon:

```
service NAME {                              <-- Supervised program (daemon)
    description = "Example daemon"          <-- Optional description
    runlevel    = "2345"                    <-- Optional runlevels
    conditions  = { "net/route/default" }   <-- Optional conditions
    envfile     = "-/etc/default/daemon"    <-- Optional env. file
    log { }                                 <-- Redirect output to log
    command     = "daemon ARGS"             <-- Path to daemon, and its arguments
}
```

Only `command` is required, which makes simple cases short while leaving
room for more advanced uses:

    service sshd {
        command = "/usr/sbin/sshd -D"
    }

Dependencies are handled using [conditions](conditions.md).  One of
the most common conditions is to wait for basic networking to become
available:

    service nginx {
        description = "High performance HTTP server"
        conditions  = { "net/route/default" }
        command     = "nginx"
    }

Here is another example where we instruct Finit to not start BusyBox
`ntpd` until `syslogd` has started properly.  Finit waits for `syslogd`
to create its PID file, by default `/var/run/syslogd.pid`.

    service ntpd {
        runlevel      = "2345"
        conditions    = { "pid/syslogd" }
        reload-signal = "none"
        log { }
        command       = "ntpd -n -N -p pool.ntp.org"
    }

    service syslogd {
        description = "Syslog daemon"
        runlevel    = "S12345"
        command     = "syslogd -n"
    }

Notice the empty `log` block, BusyBox `ntpd` uses `stderr` for logging
when run in the foreground.  With it Finit redirects `stdout` +
`stderr` to the system log daemon using the command line `logger(1)`
tool.

A service, or task, can have multiple dependencies listed.  Here we wait
for *both* `syslogd` to have started and basic networking to be up:

    service ntpd {
        runlevel   = "2345"
        conditions = { "pid/syslogd", "net/route/default" }
        log { }
        command    = "ntpd -n -N -p pool.ntp.org"
    }

If either condition fails, e.g. loss of networking, `ntpd` is stopped
and as soon as it comes back up again `ntpd` is restarted automatically.

> [!NOTE]
> Make sure daemons do *not* fork and detach themselves from the controlling
> TTY, usually an `-n` or `-f` flag, or `-D` as in the case of OpenSSH above.
> If it detaches itself, Finit cannot monitor it and will instead try to
> restart it.

[finit.conf(5)]: https://man.troglobit.com/man5/finit.conf.5.html
[infix]:         https://kernelkit.github.io
[myLinux]:       https://github.com/troglobit/myLinux/
[contrib]:       https://github.com/finit-project/finit/tree/master/contrib
