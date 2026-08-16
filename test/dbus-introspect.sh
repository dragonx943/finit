#!/bin/sh
# libink: introspection XML well-formedness.
#
# Covers compound type signatures in generated introspection XML:
# Cond1.Dump declares out_sig "a(ss)", which must appear as a single
# <arg>, not one <arg> per signature character.

set -eu

TEST_DIR=$(dirname "$0")

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"
# shellcheck source=/dev/null
. "$TEST_DIR/lib/dbus-setup.sh"

say "Introspect on /org/finit/cond"
xml=$(texec "$CLIENT" introspect "$BUS" /org/finit/cond)

say "Cond1.Dump advertises a single a(ss) out arg"
case "$xml" in
    *'<arg type="a(ss)" direction="out"/>'*) assert "a(ss) intact" 0 -eq 0 ;;
    *) fail "a(ss) not found as a single arg" ;;
esac

say "No per-character type fragments in the XML"
case "$xml" in
    *'type="("'* | *'type=")"'* | *'type="{"'* | *'type="}"'* | *'type="a"'*)
        fail "per-character <arg> fragment leaked" ;;
    *) assert "no bracket/array fragments" 0 -eq 0 ;;
esac

# ---------- <signal> declarations ----------

say "Cond1 declares the ConditionChanged signal"
case "$xml" in
    *'<signal name="ConditionChanged">'*) assert "ConditionChanged declared" 0 -eq 0 ;;
    *) fail "ConditionChanged missing from Cond1 XML" ;;
esac

say "Manager1 declares ServiceStateChanged and RunlevelChanged"
mgr=$(texec "$CLIENT" introspect "$BUS" /org/finit/manager)
case "$mgr" in
    *'<signal name="ServiceStateChanged">'*'<signal name="RunlevelChanged">'*)
        assert "Manager1 signals declared" 0 -eq 0 ;;
    *) fail "Manager1 signal declarations missing" ;;
esac

say "Properties declares PropertiesChanged, org.freedesktop.DBus is present"
case "$mgr" in
    *'<signal name="PropertiesChanged">'*) assert "PropertiesChanged declared" 0 -eq 0 ;;
    *) fail "PropertiesChanged missing from Properties XML" ;;
esac
# Hello/AddMatch/RemoveMatch are answered on the canonical object
# only, so they must be declared there and nowhere else.
drv=$(texec "$CLIENT" introspect "$BUS" /org/freedesktop/DBus)
case "$drv" in
    *'<interface name="org.freedesktop.DBus">'*) assert "org.freedesktop.DBus declared on canonical object" 0 -eq 0 ;;
    *) fail "org.freedesktop.DBus missing from /org/freedesktop/DBus" ;;
esac
case "$mgr" in
    *'<interface name="org.freedesktop.DBus">'*) fail "org.freedesktop.DBus leaked onto /org/finit/manager" ;;
    *) assert "org.freedesktop.DBus not advertised off-path" 0 -eq 0 ;;
esac
