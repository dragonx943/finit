#!/bin/sh
# Verify 'provides': a block asserts conditions beyond its own
# pid/<ident>, so variants with distinct titles can supply one
# barrier.  A claim on a condition somebody already owns is refused,
# with the service itself still registered.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
# Only the udev variant qualifies, mdevd is not a known service here,
# so syslogd:udev is the one that gets to supply pid/syslogd.
BOOTSTRAP="service anchor {
    runlevel = \"S12345\"
    command  = \"serv -np -i anchor\"
}
service syslogd:udev {
    runlevel   = \"S12345\"
    if         = \"anchor\"
    provides   = \"pid/syslogd\"
    command    = \"serv -np -i sysudev\"
}
service syslogd:mdev {
    runlevel   = \"S12345\"
    if         = \"mdevd\"
    provides   = \"pid/syslogd\"
    command    = \"serv -np -i sysmdev\"
}
service downstream {
    runlevel   = \"S12345\"
    conditions = { \"pid/syslogd\" }
    command    = \"serv -np -i downstream\"
}"

# initctl status prints a detail block for a single match and a table
# only for several, so count lines in the full listing instead.
assert_loaded()
{
    assert "Service $1 loaded: $2" \
	   "$(texec initctl -t status | awk -v n="$1" '$2 == n' | wc -l)" -eq "$2"
}

# The IDENT column of 'initctl cond dump' names the owner of a
# condition, which for a provided one is the service that claimed it.
assert_provider()
{
    assert "Condition $1 provided by $2" \
	   "$(texec initctl cond dump | awk -v c="<$1>" '$4 == c {print $2}')" = "$2"
}

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_CONF"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'The qualifying variant is loaded, the other is pruned by if'
retry 'assert_status syslogd:udev running'
assert_loaded syslogd:mdev 0

say 'It asserts the condition it provides, on top of its own'
retry 'assert_cond pid/syslogd'
assert_cond pid/syslogd:udev

say 'A service waiting on the provided condition starts'
retry 'assert_status downstream running'

say 'initctl cond dump names the provider, not "unknown"'
assert_provider pid/syslogd syslogd:udev

say 'Stopping the provider clears what it provided'
run "initctl stop syslogd:udev"
retry 'assert_nocond pid/syslogd'

run "initctl start syslogd:udev"
retry 'assert_cond pid/syslogd'

# With a BOOTSTRAP the test is released in runlevel S, where a reload
# is ignored, so wait for the runlevel change before rewriting.
say 'Waiting for bootstrap to finish before rewriting the configuration'
retry "test \"\$(texec sh -c \"initctl runlevel | awk '{print \\\$2;}'\")\" = 2" 20 1

# The claim is refused, but the service is still registered and runs.
# Both blocks qualify here, which is the configuration bug the warning
# exists for.
say 'A second claim on the same condition is refused, the service still runs'
run "echo 'service first {'                          >  $FINIT_CONF"
run "echo '    provides = \"usr/barrier\"'           >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i first\"'     >> $FINIT_CONF"
run "echo '}'                                        >> $FINIT_CONF"
run "echo 'service second {'                         >> $FINIT_CONF"
run "echo '    provides = \"usr/barrier\"'           >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i second\"'    >> $FINIT_CONF"
run "echo '}'                                        >> $FINIT_CONF"
run "initctl reload"

retry 'assert_status first running'
assert_status second running
assert_provider usr/barrier first

# A real service by that identity outranks a claim on it.
say 'An identity beats a claim on the same condition'
run "echo 'service realsvc {'                        >  $FINIT_CONF"
run "echo '    command  = \"serv -np -i realsvc\"'   >> $FINIT_CONF"
run "echo '}'                                        >> $FINIT_CONF"
run "echo 'service pretender {'                      >> $FINIT_CONF"
run "echo '    provides = \"pid/realsvc\"'           >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i pretender\"' >> $FINIT_CONF"
run "echo '}'                                        >> $FINIT_CONF"
run "initctl reload"

retry 'assert_status pretender running'
assert_provider pid/realsvc realsvc

say 'A value without a namespace is rejected, the service still runs'
run "echo 'service nonamespace {'                      >  $FINIT_CONF"
run "echo '    provides = \"syslogd\"'                 >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i nonamespace\"' >> $FINIT_CONF"
run "echo '}'                                          >> $FINIT_CONF"
run "initctl reload"

retry 'assert_status nonamespace running'

# Claims are dropped before the .conf files are re-read, so a service
# re-registering cannot lose to a claim another one has not yet
# dropped.  Without that, ownership flips on every reload.
say 'Ownership survives a reload, it does not flip between variants'
run "echo 'service keeper {'                        >  $FINIT_CONF"
run "echo '    provides = \"usr/kept\"'             >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i keeper\"'   >> $FINIT_CONF"
run "echo '}'                                       >> $FINIT_CONF"
run "echo 'service loser {'                         >> $FINIT_CONF"
run "echo '    provides = \"usr/kept\"'             >> $FINIT_CONF"
run "echo '    command  = \"serv -np -i loser\"'    >> $FINIT_CONF"
run "echo '}'                                       >> $FINIT_CONF"
run "initctl reload"
retry 'assert_provider usr/kept keeper'

run "initctl reload"
retry 'assert_provider usr/kept keeper'
run "initctl reload"
retry 'assert_provider usr/kept keeper'
