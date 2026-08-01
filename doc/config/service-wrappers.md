Service Wrapper Scripts
=======================

If your service requires to run additional commands, executed before the
service is actually started, like the systemd `ExecStartPre`, you can
use a wrapper shell script to start your service.

The Finit service `.conf` file can be put into `/etc/finit.d/available`,
so you can control the service using `initctl`.  Then use the path to
the wrapper script in the Finit `.conf` service block.  The following
example employs a wrapper script in `/etc/start.d`.

**Example:**

* `/etc/finit.d/available/program.conf`:

        service program {
            description   = "Example Program"
            runlevel      = "235"
            reload-signal = "none"
            command       = "/etc/start.d/program"
        }

* `/etc/start.d/program:`

        #!/bin/sh
        # Prepare the command line options
        OPTIONS="-u $(cat /etc/username)"

        # Execute the program
        exec /usr/bin/program $OPTIONS

> [!NOTE]
> The example sets `reload-signal = "none"` to say the program does not
> support `SIGHUP`.  Finit then stop/starts the service instead of
> signalling it at restart/reload events.
