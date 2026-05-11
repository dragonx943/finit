#!/bin/sh
# Regression: Finit must remove a daemon-owned (pid:!) stale pidfile
# left behind by an unclean exit (SIGKILL), so the next instance can
# start.  Simulates the dbus-daemon pattern: 'serv -x' refuses to
# start if its pidfile already exists.

set -eu

TEST_DIR=$(dirname "$0")
PIDFN="/run/serv.pid"

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_CONF $PIDFN"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say "Add service stanza '$FINIT_CONF' with pid:!$PIDFN"
run "echo 'service pid:!$PIDFN serv -np -P $PIDFN -x' > $FINIT_CONF"
run "initctl reload"

retry "assert_num_children 1 serv"
assert_is_pidfile "serv" "$PIDFN"

PID=$(texec cat "$PIDFN")
say "SIGKILL serv ($PID) -- leaves stale pidfile"
run "kill -9 $PID"

# Without the fix, 'serv -x' refuses to start on each retry until
# Finit hits restart_max and marks the service crashed.  With the fix
# Finit removes the stale pidfile and the next instance comes up.
retry "assert_pidiff serv $PID"
retry "assert_num_children 1 serv"

sep
