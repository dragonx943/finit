#!/bin/sh
# Verify the per-service directory settings: runtime-dir, state-dir,
# cache-dir, logs-dir, and config-dir.  The directory is created before
# the service starts, owned by the service user, and exported to the
# environment.  The runtime directory is removed again when the service
# stops, the others persist.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
BOOTSTRAP="service owned {
    runlevel    = \"S12345\"
    user        = \"daemon\"
    group       = \"daemon\"
    runtime-dir = \"owned\"
    state-dir   = \"owned\"
    pidfile     = \"/run/owned/serv.pid\"
    command     = \"/sbin/serv -np -P /run/owned/serv.pid -i owned -e STATE_DIRECTORY:/var/lib/owned\"
}
task probe {
    runlevel    = \"S12345\"
    runtime-dir = \"probe\"
    cache-dir   = \"probe\"
    command     = \"/sbin/serv -h -e RUNTIME_DIRECTORY:/run/probe -e CACHE_DIRECTORY:/var/cache/probe\"
}
service escape {
    runlevel    = \"S12345\"
    runtime-dir = \"../escape\"
    command     = \"serv -np -i escape\"
}
service modes {
    runlevel             = \"S12345\"
    user                 = \"daemon\"
    runtime-dir          = \"modes\"
    runtime-dir-mode     = 0700
    runtime-dir-preserve = \"restart\"
    config-dir           = \"modes\"
    command              = \"/sbin/serv -np -P /run/modes/serv.pid -i modes\"
}"

# ls output is empty for an empty directory, so test -d instead
assert_dir()
{
    assert "Directory $1 exists" "$(texec test -d "$1" && echo yes)" = "yes"
}

assert_nodir()
{
    assert "Directory $1 removed" "$(texec test -d "$1" || echo gone)" = "gone"
}

assert_owner()
{
    assert "$1 owned by $2" "$(texec stat -c %U:%G "$1")" = "$2"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'Directory created before start, owned by the service user'
retry 'assert_status owned running'
assert_dir /run/owned
assert_owner /run/owned daemon:daemon
assert_dir /var/lib/owned
assert_owner /var/lib/owned daemon:daemon

say 'The paths are exported to the process environment; both commands'
say 'verify their own with serv -e, and refuse to run on a mismatch'

say 'A completed task no longer holds its runtime directory'
retry 'assert_status probe done'
assert_nodir /run/probe
assert_dir /var/cache/probe

say 'Stopping the service removes the runtime directory, state persists'
run "initctl stop owned"
retry 'assert_status owned stopped'
assert_nodir /run/owned
assert_dir /var/lib/owned

say 'Starting again recreates it'
run "initctl start owned"
retry 'assert_status owned running'
assert_dir /run/owned

say 'A path escaping the base directory is refused, service still runs'
retry 'assert_status escape running'
assert_nodir /escape

say 'runtime-dir-mode sets the mode, config-dir is never chowned'
retry 'assert_status modes running'
assert "mode is 0700" "$(texec stat -c %a /run/modes)" = "700"
assert_owner /run/modes daemon:root
assert_owner /etc/modes root:root

say 'runtime-dir-preserve restart keeps the directory across a restart'
run "touch /run/modes/keepsake" || texec touch /run/modes/keepsake
run "initctl restart modes"
retry 'assert_status modes running'
assert_file_exists /run/modes/keepsake

say 'but a real stop still removes it'
run "initctl stop modes"
retry 'assert_status modes stopped'
assert_nodir /run/modes

say 'An existing directory with the wrong owner is chowned back, and'
say 'its mode is locked down again'
run "initctl stop owned"
retry 'assert_status owned stopped'
texec mkdir -p /var/lib/owned/sub
texec touch /var/lib/owned/sub/file
texec chown -R 0:0 /var/lib/owned
texec chmod 0700 /var/lib/owned
run "initctl start owned"
retry 'assert_status owned running'
assert "mode locked down to 0755" "$(texec stat -c %a /var/lib/owned)" = "755"
assert_owner /var/lib/owned daemon:daemon
assert_owner /var/lib/owned/sub/file daemon:daemon
