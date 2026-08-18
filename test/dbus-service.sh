#!/bin/sh
# libink: org.finit.Service1 vtable + ServiceStateChanged signal.
#
# Covers per-service objects exposed at /org/finit/service/<encoded>:
# GetService lookup, Introspect on a service object, Service1
# properties via Properties.Get, Service1.Restart, authorization
# (non-root rejected), and the Manager1.ServiceStateChanged signal
# that Service1.Restart triggers.

set -eu

TEST_DIR=$(dirname "$0")

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"
# shellcheck source=/dev/null
. "$TEST_DIR/lib/dbus-setup.sh"

say "Manager1.GetService(keventd) returns the encoded object path"
path=$(texec "$CLIENT" get-service "$BUS" keventd)
expected="/org/finit/service/keventd"
assert "GetService returned expected path (got: $path)" "$path" = "$expected"

say "Introspect on the service object exposes Service1 methods"
xml=$(texec "$CLIENT" introspect "$BUS" /org/finit/service/keventd)
case "$xml" in
    *'org.finit.Service1'*'Restart'*)
        assert "Service1.Restart visible in service-object XML" 0 -eq 0 ;;
    *)
        fail "Service1 not visible on /org/finit/service/keventd: $xml" ;;
esac

say "Service1 properties: Identity, State, Pid"
ident=$(texec "$CLIENT" getprop "$BUS" /org/finit/service/keventd \
	org.finit.Service1 Identity)
assert "Identity is keventd (got: $ident)" "$ident" = "keventd"

state=$(texec "$CLIENT" getprop "$BUS" /org/finit/service/keventd \
	org.finit.Service1 State)
assert "State is running (got: $state)" "$state" = "running"

pid=$(texec "$CLIENT" getprop "$BUS" /org/finit/service/keventd \
	org.finit.Service1 Pid)
assert "Pid is non-zero (got: $pid)" "$pid" -gt 0

say "Service1 properties are advertised in introspection XML"
case "$xml" in
    *'<property name="Identity" type="s"'*'<property name="Pid" type="u"'*)
        assert "Identity and Pid declared with types" 0 -eq 0 ;;
    *)
        fail "Property declarations missing from service XML" ;;
esac

say "Service1.Restart on /org/finit/service/keventd succeeds"
texec "$CLIENT" call-void "$BUS" /org/finit/service/keventd \
    org.finit.Service1 Restart >/dev/null \
    || fail "Service1.Restart returned non-zero"
assert "Per-service Restart ok" 0 -eq 0

# See dbus-manager.sh: widen the test socket so a non-member reaches
# the method-level authz behind the 0660 gate.
bus_open_to_all
say "Service1.Restart from non-root is rejected with AccessDenied"
set +e
texec "$CLIENT" call-void-as-uid 1 "$BUS" /org/finit/service/keventd \
    org.finit.Service1 Restart >/tmp/dbus-svcauthz.out 2>&1
svc_authz_rc=$?
set -e
assert "Non-root Service1.Restart rejected (rc=$svc_authz_rc)" \
    "$svc_authz_rc" -eq 1
case "$(cat /tmp/dbus-svcauthz.out)" in
    *AccessDenied*) assert "Service1 authz fires" 0 -eq 0 ;;
    *) fail "Expected AccessDenied, got: $(cat /tmp/dbus-svcauthz.out)" ;;
esac

say "Service1.Restart fires Manager1.ServiceStateChanged"
rm -f /tmp/dbus-sig.out
( texec "$CLIENT" monitor-signal "$BUS" \
    "type='signal',interface='org.finit.Manager1',member='ServiceStateChanged'" \
    5000 > /tmp/dbus-sig.out 2>&1 ) &
mon_pid=$!
sleep 0.5
texec "$CLIENT" call-void "$BUS" /org/finit/service/keventd \
    org.finit.Service1 Restart >/dev/null \
    || fail "Restart trigger returned non-zero"
set +e
wait "$mon_pid"
mon_rc=$?
set -e
assert "monitor saw a signal (rc=$mon_rc)" "$mon_rc" -eq 0
case "$(cat /tmp/dbus-sig.out)" in
    *"SIGNAL org.finit.Manager1 ServiceStateChanged"*keventd*)
        assert "Signal payload contains the keventd identity" 0 -eq 0 ;;
    *)
        fail "Unexpected signal output: $(cat /tmp/dbus-sig.out)" ;;
esac

# ---------- name:id identities and _HH path encoding ----------

say "Manager1.GetService(dhcp-client:eth1) hex-escapes the object path"
cat >> "$SYSROOT$FINIT_CONF" <<CONF
service dhcp-client:eth1 {
    manual  = true
    command = "serv -np"
}
CONF
run "initctl reload"
epath=$(texec "$CLIENT" get-service "$BUS" "dhcp-client:eth1")
assert "Encoded path (got: $epath)" "$epath" = "/org/finit/service/dhcp_2dclient_3aeth1"

say "The encoded service object introspects and answers Properties.Get"
exml=$(texec "$CLIENT" introspect "$BUS" "$epath")
case "$exml" in
    *'org.finit.Service1'*) assert "Service1 on encoded path" 0 -eq 0 ;;
    *) fail "Service1 missing on $epath" ;;
esac
eident=$(texec "$CLIENT" getprop "$BUS" "$epath" org.finit.Service1 Identity)
assert "Identity round-trips (got: $eident)" "$eident" = "dhcp-client:eth1"
