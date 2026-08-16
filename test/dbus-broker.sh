#!/bin/sh
# Finit against a real message bus.
#
# Every other dbus-*.sh test drives libink's own client, so the wire
# format is only ever checked against the implementation that produced
# it.  Here the dbus plugin brings up a real dbus-daemon, Finit finds
# it and claims org.finit, and then dbus-send talks to Finit: a client
# that shares no code with us.
#
# It also covers the only path the brokerless bus cannot reach, where
# one connection carries every caller and Finit has to ask the broker
# who sent each privileged call.
#
# Skipped when the host has no dbus-daemon or dbus-send to stage.

set -eu

TEST_DIR=$(dirname "$0")

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

# Staged by lib/sysroot.mk from the host, when it has them.
for prog in dbus-daemon dbus-send; do
    texec sh -c "command -v $prog >/dev/null" \
	|| skip "no $prog in the test root, need it on the host"
done

say 'The dbus plugin started a system bus'
retry 'assert_file_exists /var/run/dbus/system_bus_socket'

say 'Finit claims org.finit on the system bus'
retry "texec dbus-send --system --print-reply --dest=org.freedesktop.DBus \
       /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner string:org.finit" 60 0.5

say 'A read-only method answers through the broker'
list=$(texec dbus-send --system --print-reply --dest=org.finit \
       /org/finit/manager org.finit.Manager1.ListServices)
assert "ListServices returned the dbus service" \
       "$(printf '%s' "$list" | grep -c '"dbus"')" -ge 1

say 'Properties.Get answers through the broker'
rl=$(texec dbus-send --system --print-reply --dest=org.finit \
     /org/finit/manager org.freedesktop.DBus.Properties.Get \
     string:org.finit.Manager1 string:Runlevel)
assert "Runlevel property is 2" "$(printf '%s' "$rl" | grep -c '"2"')" -eq 1

# The point of the exercise: a privileged call over the broker means
# Finit parks it, asks the driver who the sender is, and dispatches on
# the answer.  Root is allowed, so reaching NoSuchService proves the
# whole round trip worked rather than a blanket denial.  The repeat
# call goes the same way, only answered from the sender cache.
for pass in first repeat; do
    say "A privileged method resolves the caller, $pass call"
    priv=$(texec dbus-send --system --print-reply --dest=org.finit \
	   /org/finit/manager org.finit.Manager1.Restart string:nosuchservice 2>&1 || true)
    case "$priv" in
	*NoSuchService*) assert "Caller identified on the $pass call" 0 -eq 0 ;;
	*)               fail "Unexpected reply to the $pass privileged call: $priv" ;;
    esac
done
