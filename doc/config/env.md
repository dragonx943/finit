Environment Variables
---------------------

In Finit v4.3 support for setting environment variables in `finit.conf`,
and any `*.conf`, was added.  It is worth noting that these are global
and *shared with all* services -- the only way to have a service-local
environment is detailed in [Services Environment](service-env.md).

Global environment variables go in an `environment` block, `env` for
short:

    environment {
        foo = "bar"
        baz = "qux"
    }

On reload of .conf files, all tracked environment variables are cleared
so if `foo` is removed from `finit.conf`, or any `finit.d/*.conf`
file, it will no longer be used by Finit or any new (!) started
run/tasks or services.  The environment of already started processes can
not be changed.

The only variables reset to sane defaults on .conf reload are:

    PATH=_PATH_STDPATH
    SHELL=_PATH_BSHELL
    LOGNAME=root
    USER=root

It is entirely possible to override these as well from the .conf files,
but be careful.  Changing SHELL changes the behavior of `system()` and a
lot of other commands as well.
