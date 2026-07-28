run (sequence)
--------------

**Syntax:** `run NAME { command = "/path/to/cmd ARGS" }`

> `<COND>` is described in the [Services](services.md) section.

One-shot command to run in sequence when entering a runlevel, with
optional arguments and description.  `run` commands are guaranteed to be
completed before running the next command.  Useful when serialization is
required.

> [!WARNING]
> Try to avoid the `run` command.  It blocks much of the functionality
> in Finit, like (re)starting other (perhaps crashing) services while a
> `run` task is executing.  Use other synchronization mechanisms
> instead, like conditions.

Incomplete list of unsupported `initctl` commands in `run` tasks:

 - `initctl runlevel N`, setting runlevel
 - `initctl reboot`
 - `initctl halt`
 - `initctl poweroff`
 - `initctl suspend`

To prevent `initctl` from calling Finit when enabling and disabling
services from inside a `run` task, use the `--force` option.  See
also the `--quiet` and `--batch` options.

task (parallel)
---------------

**Syntax:** `task NAME { command = "/path/to/cmd ARGS" }`

> `<COND>` is described in the [Services](services.md) section.

One-shot like 'run', but starts in parallel with the next command.
  
Both `run` and `task` commands are run in a shell, so basic pipes and
redirects can be used:

    task bar {
        runlevel = "S"
        command  = "echo \"foo\" | cat >/tmp/bar"
    }

Please note, `;`, `&&`, `||`, and similar are *not supported*.  Any
non-trivial constructs are better placed in a separate shell script.


remain-after-exit
-----------------

By default, a `run` or `task` will re-run each time its runlevel is
entered, and its `exec-stop-post` script does not run on completion.

With `remain-after-exit`, the task runs once and does not re-run on
runlevel re-entry:

    task firewall {
        description       = "Firewall setup"
        runlevel          = "2345"
        remain-after-exit = true
        command           = "/usr/sbin/setup-firewall"
    }

This has the following effects:

  * The task does not re-run on runlevel re-entry
  * The `exec-stop-post` script runs when:
    - The task is explicitly stopped (`initctl stop NAME`)
    - The task leaves its valid runlevels (e.g., runlevel change)

This is useful for tasks that set up persistent state where:

  * Cleanup should only happen on explicit stop or when leaving valid runlevels
  * The setup should not be re-run on every runlevel entry

**Example:** Setting up firewall rules with cleanup on shutdown:

```
task firewall {
    description       = "Firewall setup"
    runlevel          = "2345"
    remain-after-exit = true
    exec-stop-post    = "/usr/sbin/teardown-firewall"
    command           = "/usr/sbin/setup-firewall"
}
```

The firewall rules are created once.  The `exec-stop-post` script runs when
entering runlevel 0 (halt) or 6 (reboot), or on explicit stop.

> [!NOTE]
> The `remain-after-exit` option is not supported for bootstrap-only
> tasks (tasks with only runlevel S).  Bootstrap tasks are deleted
> immediately after completion, and their `exec-stop-post` scripts never
> run.  A warning is logged if `remain-after-exit` is used on such tasks.
