#!/bin/sh
# keventd: org.finit.Device1 on /run/keventd/bus.
#
# Covers the device manager's own bus: introspection, queue-state
# properties, Settle, Info by devpath, RulesReload, Trigger, and the
# DeviceProcessed signal.  Network interfaces are the one device class
# the unprivileged sandbox can hotplug, see keventd.sh.

set -eu

TEST_DIR=$(dirname "$0")

test_teardown()
{
    say "Running test teardown."

    run "ip link del dummy0 2>/dev/null || true"
    run "rm -f $FINIT_CONF"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"
# shellcheck source=/dev/null
. "$TEST_DIR/lib/dbus-setup.sh"

DEVBUS=/run/keventd/bus

if ! texec initctl -p status keventd >/dev/null 2>&1; then
    skip "keventd not enabled in this build"
fi
if ! run "ip link add probe0 type dummy 2>/dev/null"; then
    skip "cannot create dummy interfaces in test namespace"
fi
run "ip link del probe0"

say "keventd readiness"
retry 'assert_ready "keventd"' 50 0.2
retry "texec test -S $DEVBUS"

say "Device1 introspects with methods, properties, and signal"
xml=$(texec "$CLIENT" introspect "$DEVBUS" /org/finit/device)
for m in Settle Trigger Info RulesReload; do
    case "$xml" in
        *"<method name=\"$m\">"*) assert "$m declared" 0 -eq 0 ;;
        *) fail "$m missing from Device1 XML" ;;
    esac
done
case "$xml" in
    *'<property name="QueueEmpty" type="b"'*'<signal name="DeviceProcessed">'*)
        assert "QueueEmpty property and DeviceProcessed signal declared" 0 -eq 0 ;;
    *) fail "property/signal declarations missing: $xml" ;;
esac

say "Queue-state properties are readable"
seq1=$(texec "$CLIENT" getprop "$DEVBUS" /org/finit/device \
       org.finit.Device1 SeqnumProcessed)
assert "SeqnumProcessed is numeric (got: $seq1)" "$seq1" -ge 0
qe=$(texec "$CLIENT" getprop "$DEVBUS" /org/finit/device \
     org.finit.Device1 QueueEmpty)
case "$qe" in
    true|false) assert "QueueEmpty reads $qe" 0 -eq 0 ;;
    *) fail "Unexpected QueueEmpty value: $qe" ;;
esac

say "Device1.Settle answers within its timeout"
texec "$CLIENT" call-u "$DEVBUS" /org/finit/device \
    org.finit.Device1 Settle 15 >/dev/null \
    || fail "Settle returned non-zero"
assert "Settle completed" 0 -eq 0

say "Interface add advances SeqnumProcessed and Info answers"
run "ip link add dummy0 type dummy"
retry 'assert_cond "class/net/dummy0"'
seq2=$(texec "$CLIENT" getprop "$DEVBUS" /org/finit/device \
       org.finit.Device1 SeqnumProcessed)
assert "SeqnumProcessed advanced ($seq1 -> $seq2)" "$seq2" -gt "$seq1"

info=$(texec "$CLIENT" call-s "$DEVBUS" /org/finit/device \
       org.finit.Device1 Info /devices/virtual/net/dummy0 2>&1) \
    || fail "Info failed: $info"
assert "Info answered for dummy0" 0 -eq 0

say "keventd -S settles via the bus"
run "/libexec/finit/keventd -S -t 15" || fail "keventd -S failed"
assert "bus-first settle ok" 0 -eq 0

say "Trigger(add, net) re-emits events, DeviceProcessed observed"
rm -f /tmp/dbus-dev-sig.out
( texec "$CLIENT" monitor-signal "$DEVBUS" \
    "type='signal',interface='org.finit.Device1',member='DeviceProcessed'" \
    5000 > /tmp/dbus-dev-sig.out 2>&1 ) &
mon_pid=$!
sleep 0.5
texec "$CLIENT" call-ss "$DEVBUS" /org/finit/device \
    org.finit.Device1 Trigger add net >/dev/null 2>&1 \
    || fail "Trigger returned non-zero"
set +e
wait "$mon_pid"
mon_rc=$?
set -e
assert "monitor saw DeviceProcessed (rc=$mon_rc)" "$mon_rc" -eq 0
case "$(cat /tmp/dbus-dev-sig.out)" in
    *"DeviceProcessed"*net*) assert "Signal payload names a net device" 0 -eq 0 ;;
    *) fail "Unexpected signal output: $(cat /tmp/dbus-dev-sig.out)" ;;
esac

say "RulesReload succeeds and Trigger rejects a bogus action"
texec "$CLIENT" call-void "$DEVBUS" /org/finit/device \
    org.finit.Device1 RulesReload >/dev/null \
    || fail "RulesReload failed"
assert "RulesReload ok" 0 -eq 0

set +e
texec "$CLIENT" call-ss "$DEVBUS" /org/finit/device \
    org.finit.Device1 Trigger frobnicate "" >/tmp/dbus-trg.out 2>&1
trg_rc=$?
set -e
assert "Bogus action rejected (rc=$trg_rc)" "$trg_rc" -eq 1
case "$(cat /tmp/dbus-trg.out)" in
    *InvalidArgs*) assert "Error is InvalidArgs" 0 -eq 0 ;;
    *) fail "Unexpected reply: $(cat /tmp/dbus-trg.out)" ;;
esac

say "Device1.RulesReload from non-root is rejected with AccessDenied"
texec chmod 0666 "$DEVBUS"
set +e
texec "$CLIENT" call-void-as-uid 1 "$DEVBUS" /org/finit/device \
    org.finit.Device1 RulesReload >/tmp/dbus-devauthz.out 2>&1
dauthz_rc=$?
set -e
assert "Non-root RulesReload rejected (rc=$dauthz_rc)" "$dauthz_rc" -eq 1
case "$(cat /tmp/dbus-devauthz.out)" in
    *AccessDenied*) assert "Device1 authz fires" 0 -eq 0 ;;
    *) fail "Unexpected reply: $(cat /tmp/dbus-devauthz.out)" ;;
esac
