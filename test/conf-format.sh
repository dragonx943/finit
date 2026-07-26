#!/bin/sh
# Verify the new libconfuse config format: block -> legacy translation,
# per-file format detection (legacy files keep working alongside), and
# that a typo in a new-format file is rejected with an error instead of
# being fed to the legacy parser.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
# A /etc/finit.conf entirely in the new format, seeded before Finit
# boots.  Mixing the two formats in one file is not supported, so the
# probe that reads the variable back is a block too.
BOOTSTRAP="environment {\n\
    CONF_FORMAT_VAR = \"blockfmt\"\n\
}\n\
run envprobe {\n\
    runlevel    = \"S\"\n\
    description = \"Probe\"\n\
    command     = \"/bin/touch /tmp/envprobe-\$CONF_FORMAT_VAR\"\n\
}"

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_CONF /tmp/envprobe-* /tmp/pre /run/blockfmt.pid /run/notmine.pid"
    run "rm -f $FINIT_RCSD/legacy-side.conf"
}

# Write a service block, $1 is the description key, to exercise both
# the canonical spelling and a typo.  $2, if given, is prepended as a
# root-level line.
write_svc()
{
    run "echo '${2:-}service service.sh {'          >  $FINIT_CONF"
    run "echo '    $1 = \"Test service\"'           >> $FINIT_CONF"
    run "echo '    command = \"service.sh\"'        >> $FINIT_CONF"
    run "echo '}'                                   >> $FINIT_CONF"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'A new-format /etc/finit.conf booted the system, environment {} applied'
retry 'assert_file_exists /tmp/envprobe-blockfmt'

# Reaching runlevel 2 reloads the .conf files, and conf_reset_env()
# clears every tracked variable first.  Gating environment {} on
# bootstrap would therefore drop it here, which is what serv -e
# catches: it exits unless the variable still holds the value.
say 'Global env survives the runlevel change and a reload, via the env {} alias'
run "echo 'env {'                                  >  $FINIT_CONF"
run "echo '    CONF_FORMAT_VAR = \"blockfmt\"'     >> $FINIT_CONF"
run "echo '}'                                      >> $FINIT_CONF"
run "echo 'service serv {'                         >> $FINIT_CONF"
run "echo '    description = \"Verify env\"'       >> $FINIT_CONF"
run "echo '    command = \"serv -np -e CONF_FORMAT_VAR:blockfmt\"' >> $FINIT_CONF"
run "echo '}'                                      >> $FINIT_CONF"
run "initctl reload"

retry 'assert_num_children 1 serv'
assert_desc "Verify env" serv

say "Add new-format service block in $FINIT_CONF"
run "echo 'service service.sh {'                    >  $FINIT_CONF"
run "echo '    description = \"Test service\"'     >> $FINIT_CONF"
run "echo '    runlevel    = \"2345\"'             >> $FINIT_CONF"
run "echo '    stop-timeout = 20'                   >> $FINIT_CONF"
run "echo '    log { }'                 >> $FINIT_CONF"
# Exercises the cgroup translation path.  Whether the group is really
# joined cannot be asserted here, cgroup_avail() is false inside the
# test namespace, so initctl reports no cgroup at all.
run "echo '    cgroup user {}'                     >> $FINIT_CONF"
run "echo '    command     = \"service.sh\"'       >> $FINIT_CONF"
run "echo '}'                                      >> $FINIT_CONF"

say 'Reload Finit'
run "initctl reload"

retry 'assert_num_children 1 service.sh'
assert_desc "Test service" service.sh

say 'Stop the service'
run "initctl stop service.sh"

retry 'assert_num_children 0 service.sh'

say 'Start the service again'
run "initctl start service.sh"

retry 'assert_num_children 1 service.sh'

say 'Both formats side by side: legacy file in finit.d/, block file in finit.conf'
run "echo 'task [2345] name:legacyside /bin/touch /tmp/legacyside -- Legacy side' > $FINIT_RCSD/legacy-side.conf"
run "initctl reload"

retry 'assert_file_exists /tmp/legacyside'
retry 'assert_num_children 1 service.sh'
assert_desc "Legacy side" legacyside

run "rm -f $FINIT_RCSD/legacy-side.conf /tmp/legacyside"
run "initctl reload"

say 'Round-trip: switch to the legacy one-liner equivalent'
run "echo 'service [2345] name:service.sh kill:20 log service.sh -- Test service' > $FINIT_CONF"
run "initctl reload"

retry 'assert_num_children 1 service.sh'
assert_desc "Test service" service.sh

# A rejected file must not reach the legacy parser, which registers a
# bogus unstartable service per line.  assert_num_children cannot see
# that, the bogus service has no children either.
say 'Typo inside a block must be rejected, not fed to legacy parser'
write_svc descriptoin
run "initctl reload"

retry 'assert_num_children 0 service.sh'
assert_num_services 0 service.sh

say 'Typo at root level must be rejected too, same as inside a block'
write_svc description 'hostnam = \"typo\"\n'
run "initctl reload"

retry 'assert_num_children 0 service.sh'
assert_num_services 0 service.sh

say 'A clean new-format file still loads after the rejected ones'
write_svc description
run "initctl reload"

retry 'assert_num_children 1 service.sh'
assert_desc "Test service" service.sh

# The renamed and split settings each have translation logic behind
# them, so exercise the ones with a visible effect.
# Only the warning differs, service_register() bails before svc_new()
# either way, so this asserts the stanza is skipped, not that the
# warning was suppressed.  The emitted one-liner is where nowarn is
# visible, with finit.debug=on.
say 'A leading - on command tolerates a missing binary'
run "echo 'service ghost {'                        >  $FINIT_CONF"
run "echo '    description = \"Ghost\"'            >> $FINIT_CONF"
run "echo '    command     = \"-/no/such/binary\"' >> $FINIT_CONF"
run "echo '}'                                      >> $FINIT_CONF"
run "initctl reload"

assert_num_services 0 ghost

say 'exec-start-pre runs before the service, pidfile-create makes Finit own the file'
run "echo 'service service.sh {'                       >  $FINIT_CONF"
run "echo '    description    = \"Test service\"'      >> $FINIT_CONF"
run "echo '    conditions     = { \"hook/svc/up\" }'   >> $FINIT_CONF"
run "echo '    exec-start-pre = \"/bin/pre.sh\"'       >> $FINIT_CONF"
run "echo '    exec-start-pre-timeout = 5'             >> $FINIT_CONF"
run "echo '    pidfile        = \"/run/blockfmt.pid\"' >> $FINIT_CONF"
run "echo '    pidfile-create = true'                  >> $FINIT_CONF"
run "echo '    restart        = true'                  >> $FINIT_CONF"
run "echo '    restart-max    = 3'                     >> $FINIT_CONF"
run "echo '    command        = \"service.sh\"'        >> $FINIT_CONF"
run "echo '}'                                          >> $FINIT_CONF"
run "initctl reload"

retry 'assert_num_children 1 service.sh'
retry 'assert_file_exists /tmp/pre'
assert_restart_cnt 0 "0/3" service.sh

# service.sh writes /run/service.pid, never /run/blockfmt.pid, so only
# Finit can have created this one.  assert_is_pidfile cannot tell, it
# prints the path with any leading ! stripped.
retry 'assert_file_exists /run/blockfmt.pid'

say 'Without pidfile-create the daemon owns the file, Finit does not make it'
run "echo 'service service.sh {'                       >  $FINIT_CONF"
run "echo '    description = \"Test service\"'         >> $FINIT_CONF"
run "echo '    pidfile     = \"/run/notmine.pid\"'     >> $FINIT_CONF"
run "echo '    command     = \"service.sh\"'           >> $FINIT_CONF"
run "echo '}'                                          >> $FINIT_CONF"
run "rm -f /run/notmine.pid"
run "initctl reload"

retry 'assert_num_children 1 service.sh'
assert "daemon-owned pidfile is not created by Finit" \
       "$(texec ls /run/notmine.pid 2>/dev/null)" = ""
