# shellcheck shell=sh
# Shared preamble for the D-Bus smoke tests.  Expects test/lib/setup.sh
# to have been sourced already (so texec, skip, retry, say, assert are
# available).  Skips the test when the libink-driven client was not
# built, otherwise blocks until the bus socket appears.
#
# Exports: CLIENT, BUS.

command -v texec >/dev/null \
    || { echo "dbus-setup.sh: source test/lib/setup.sh first" >&2; exit 99; }

CLIENT=/sbin/dbus-auth-client
BUS=/run/finit/bus

if ! texec test -x "$CLIENT"; then
    skip "dbus-auth-client not built (configured with --disable-dbus?)"
fi

say "Wait for $BUS to appear"
retry "texec test -S $BUS"

# The installed bus stays 0660 (root + the --with-group group), so a
# caller outside that group is stopped by the socket before any method
# runs.  A few tests need to reach the per-method authorization behind
# that gate -- to prove a non-member is refused there too, not only at
# connect -- so they widen the *test* socket to 0666 first.  Real
# deployments keep 0660; this only touches the runtime socket in the
# test namespace.
bus_open_to_all()
{
    texec chmod 0666 "$BUS"
}
