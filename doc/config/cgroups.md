Finit has two `cgroup` blocks for controlling resource allocation:

 1. **Top-level definition**, at file scope: declares a group such as
    `init`, `system`, or `user`, and its default settings.

        cgroup system { cpu.weight = 9700 }

 2. **Joining a group**, inside a service block: names the group this
    service runs in, and may override settings for itself alone.

        service foo {
            cgroup maint { memory.max = 1G }
            command = "/path/to/cmd"
        }

> [!NOTE]
> Linux cgroups and details surrounding values are not explained in the
> Finit documentation.  The Linux admin-guide covers this well:
> <https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html>

Top-level Cgroup Definition
----------------------------

**Syntax:** `cgroup NAME { settings }`

    # Top-level cgroups and their default settings.  All groups mandatory
    # but more can be added, max 8 groups in total currently.  The cgroup
    # 'root' is also available, reserved for RT processes.  Settings are
    # as-is, only one shorthand 'mem.' exists, other than that it's the
    # cgroup v2 controller default names.
    cgroup init   { cpu.weight = 100  }
    cgroup user   { cpu.weight = 100  }
    cgroup system { cpu.weight = 9800 }

Adding an extra cgroup `maint/` will require you to adjust the weight of
the above three.  We leave `init/` and `user/` as-is reducing weight of
`system/` to 9700.

    cgroup system { cpu.weight = 9700 }

    # Example extra cgroup 'maint'
    cgroup maint  { cpu.weight = 100  }

By default, the `system/` cgroup is selected for almost everything.  The
`init/` cgroup is reserved for PID 1 itself and its closest relatives.
The `user/` cgroup is for local TTY logins spawned by getty.

Joining a Cgroup
----------------

**Syntax:** `cgroup NAME { settings }` (inside a service block)

Every block says which group it joins, by name.  An empty block joins
without changing anything:

    service foo {
        cgroup maint {}
        command = "/path/to/foo args"
    }

    service bar {
        cgroup maint {}
        command = "/path/to/bar args"
    }

Both services run in the `maint/` cgroup.  Settings inside the block
apply to that service alone:

    service foo {
        cgroup maint {
            cpu.max    = 10000
            memory.max = 655360
        }
        command = "/path/to/foo args"
    }

> [!NOTE]
> The legacy format has a standalone `cgroup.NAME` line that selects a
> group for every stanza following it in the file, and a `cgroup:options`
> form that applies settings to whichever group is current without
> naming it.  Neither has an equivalent here, by design: a block that
> joins a group says so itself, so the group cannot depend on what came
> earlier in the file.

Every cgroup setting maps directly to cgroup v2 syntax, so `cpu.max`
maps to the file `/sys/fs/cgroup/maint/foo/cpu.max`.  There is no
filtering, the one exception being the shorthand `mem.`, which expands
to `memory.`.  If the file is not available, either the controller is
missing from your Linux kernel, or the name is misspelled.

### Overriding Cgroup Leaf Names

By default, the cgroup leaf directory name is derived from the service
configuration filename (without the `.conf` extension). For example, a
service defined in `system/10-hotplug.conf` would create a cgroup at
`/sys/fs/cgroup/system/10-hotplug/` by default.

To use a more descriptive name (recommended for clarity), set `name`
inside the cgroup block:

    service udevd {
        description = "Device event daemon"
        cgroup system { name = "udevd" }
        command     = "/lib/systemd/systemd-udevd"
    }

This creates the cgroup at `/sys/fs/cgroup/system/udevd/` instead.

`name` combines with any other setting:

    service udevd {
        description = "Device event daemon"
        cgroup system {
            name    = "udevd"
            cpu.max = 10000
        }
        command = "/lib/systemd/systemd-udevd"
    }

Or with delegation:

    service podman {
        description = "Podman API"
        runlevel    = "2345"
        user        = "podman"
        group       = "podman"
        cgroup containers {
            name       = "podman"
            delegate   = true
            memory.max = 4G
        }
        command = "/usr/bin/podman system service"
    }

A daemon using `SCHED_RR` currently needs to run outside the default
cgroups.

    service rt {
        description = "Real-Time process"
        cgroup root {}
        command     = "/path/to/daemon arg"
    }

Cgroup Delegation
-----------------

For services that need to create their own child cgroups (container runtimes
like Docker, Podman, systemd-nspawn, LXC), set `delegate`:

    service dockerd {
        description = "Docker daemon"
        runlevel    = "2345"
        user        = "dockerd"
        group       = "dockerd"
        cgroup system { delegate = true }
        command     = "/usr/bin/dockerd"
    }

This allows the container runtime to:

- Create child cgroups for containers
- Manage controller settings for containers
- Move processes between cgroups

When delegation is enabled, Finit:

1. Creates the service cgroup as a **domain group** (not a leaf)
2. Enables all available controllers in `cgroup.subtree_control`
3. Changes ownership of delegation files to the service user
4. Moves the service process to the cgroup root
5. Lets the container runtime manage its own subdirectories

**Requirements:**

- The service should specify `user` and `group` for proper ownership
- Controllers are delegated from the parent cgroup

**Example with additional config:**

    service podman {
        description = "Podman API"
        runlevel    = "2345"
        user        = "podman"
        group       = "podman"
        cgroup containers {
            delegate   = true
            memory.max = 4G
        }
        command = "/usr/bin/podman system service"
    }

This delegates the cgroup while also setting a 4GB memory limit.

**Container template example:**

Here's a real-world example from [Infix OS](https://github.com/kernelkit/infix)
for running rootful podman container instances using delegation:

    sysv container:%i {
        description   = "container %i"
        runlevel      = "2345"
        reload-signal = "none"
        pidfile       = "/run/container:%i.pid"
        stop-timeout  = 30
        log { priority = "local1"  identity = "%i" }

        exec-start-pre         = "/usr/sbin/container"
        exec-start-pre-timeout = 0
        exec-cleanup           = "/usr/sbin/container"
        exec-cleanup-timeout   = 0

        cgroup system { delegate = true }
        command = "container -n %i"
    }

This template uses `sysv` type with delegation, demonstrating that cgroup
delegation works with different service types, not just `service`.

**Cgroup structure with delegation:**

Initially, the service process runs directly in the cgroup root:

    /sys/fs/cgroup/system/container@web/
    ├── cgroup.procs            (service PID - owned by service user)
    ├── cgroup.subtree_control  (+cpu +memory +io - owned by service user)
    └── (container children will be created here)

Once the container runtime creates child cgroups (e.g., `libpod-*/`), cgroups v2
enforces the "no internal processes" rule. When Finit detects this (`EBUSY` error),
it automatically creates a `supervisor/` subdirectory and moves service-related
processes there:

    /sys/fs/cgroup/system/container@web/
    ├── cgroup.procs            (empty)
    ├── cgroup.subtree_control  (+cpu +memory +io)
    ├── supervisor/             (service processes)
    │   └── cgroup.procs        (conmon PIDs, etc.)
    └── libpod-$HASH/           (container processes)
        └── cgroup.procs        (container PIDs)

This happens automatically - no configuration needed. Without delegation, the
cgroup would be a leaf and the container runtime could not create child cgroups.
