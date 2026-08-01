Switch Root
===========

Finit supports switching from an initramfs to a real root filesystem
using the `initctl switch-root` command.  This is useful for systems
that use an initramfs for early boot (LUKS, LVM, network boot, etc.)
and need to transition to the real root before starting services.


Usage
-----

```sh
initctl switch-root NEWROOT [INIT]
```

- `NEWROOT`: Path to the mounted new root filesystem (e.g., `/mnt/root`)
- `INIT`: Optional path to init on the new root (default: `/sbin/init`)


Requirements
------------

1. Must be run during runlevel S (bootstrap) or runlevel 1
2. `NEWROOT` must be a mount point (different device than /)
3. `INIT` must exist and be executable on the new root
4. Finit must be running as PID 1 (in initramfs)


How It Works
------------

1. Runs `HOOK_SWITCH_ROOT` for any cleanup scripts/plugins
2. Runs `HOOK_SHUTDOWN` to notify plugins
3. Stops all services and kills remaining processes
4. Exits all plugins gracefully
5. Moves `/dev`, `/proc`, `/sys`, `/run` to new root
6. Deletes initramfs contents (if on tmpfs/ramfs) to free memory
7. Moves new root mount to `/`
8. Chroots to new root
9. Reopens `/dev/console` for stdin/stdout/stderr
10. Execs new init as PID 1


Example: Initramfs finit.conf
-----------------------------

Configuration file `/etc/finit.conf` in the initramfs:

```
# /etc/finit.conf in initramfs

# Mount the real root filesystem
run mount-root {
    description = "Mounting root filesystem"
    runlevel    = "S"
    command     = "/bin/mount /dev/sda1 /mnt/root"
}

# Switch to real root after mount completes
run switch-root {
    description = "Switching to real root"
    runlevel    = "S"
    command     = "/sbin/initctl switch-root /mnt/root"
}
```

For more complex setups (LUKS, LVM, etc.):

```
# Unlock LUKS volume
# The tty setting is required so cryptsetup can prompt for a passphrase
run cryptsetup {
    description = "Unlocking encrypted root"
    runlevel    = "S"
    tty         = "@console"
    command     = "/sbin/cryptsetup open /dev/sda2 cryptroot"
}

# Activate LVM
run lvm {
    description = "Activating LVM volumes"
    runlevel    = "S"
    command     = "/sbin/lvm vgchange -ay"
}

# Mount root
run mount-root {
    description = "Mounting root"
    runlevel    = "S"
    command     = "/bin/mount /dev/vg0/root /mnt/root"
}

# Switch root
run switch-root {
    description = "Switching to real root"
    runlevel    = "S"
    command     = "/sbin/initctl switch-root /mnt/root"
}
```


Example: Using Runlevel 1 for Switch Root
-----------------------------------------

For more complex initramfs setups where ordering of tasks becomes
difficult in runlevel S, you can perform the switch-root in runlevel 1:

```
# /etc/finit.conf in initramfs

# Start mdevd for device handling
service mdevd {
    description = "Device event daemon"
    runlevel    = "S"
    notify      = "s6"
    command     = "/sbin/mdevd -D %n"
}
run coldplug {
    description = "Coldplug devices"
    runlevel    = "S"
    conditions  = { "service/mdevd/ready" }
    command     = "/sbin/mdevd-coldplug"
}

# Mount the real root filesystem (after devices are ready)
run mount-root {
    description = "Mounting root"
    runlevel    = "S"
    conditions  = { "run/coldplug/success" }
    command     = "/bin/mount /dev/sda1 /mnt/root"
}

# Transition to runlevel 1 after all S tasks complete
# The switch-root runs cleanly in runlevel 1
run switch-root {
    description = "Switching to real root"
    runlevel    = "1"
    command     = "/sbin/initctl switch-root /mnt/root"
}
```

This approach separates the initramfs setup (runlevel S) from the
switch-root operation (runlevel 1), making task ordering simpler.


Hooks
-----

The `HOOK_SWITCH_ROOT` hook runs before the switch begins.  Use it for:

- Saving state to the new root
- Unmounting initramfs-only mounts
- Cleanup tasks

Plugins can register for `HOOK_SWITCH_ROOT` just like other hooks:

```c
static void my_switch_root_hook(void *arg)
{
    /* Cleanup before switch_root */
}

static plugin_t plugin = {
    .name = "my-plugin",
    .hook[HOOK_SWITCH_ROOT] = {
        .cb = my_switch_root_hook
    }
};

PLUGIN_INIT(plugin_init)
{
    plugin_register(&plugin);
}
```


Conditions
----------

After switch_root, the new finit instance starts fresh.  No conditions
or state are preserved across the switch.  The new finit will:

1. Re-read `/etc/finit.conf` from the new root
2. Re-initialize all conditions
3. Start services according to the new configuration


See Also
--------

- [switch_root(8)](https://man7.org/linux/man-pages/man8/switch_root.8.html) - util-linux switch_root utility
- [Kernel initramfs documentation](https://docs.kernel.org/filesystems/ramfs-rootfs-initramfs.html)
