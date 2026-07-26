#!/bin/sh
# Verify %i template instantiation for both .conf formats: the block
# format substitutes over the whole file before parsing, the legacy
# one-liner format per line.  A bare name@.conf registers nothing.
set -eu

TEST_DIR=$(dirname "$0")

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_RCSD/available/serv@.conf"
    run "rm -f $FINIT_RCSD/enabled/serv@eth0.conf"
    run "rm -f $FINIT_RCSD/enabled/serv@eth1.conf $FINIT_RCSD/enabled/serv@.conf"
    run "rm -f /run/serv-eth0.pid /run/serv-eth1.pid"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

# %i has to reach three different places: the section title, which
# becomes the instance identity, an ordinary value, and the command
# line.  The per-instance PID file covers the last one, it can only
# appear if the command was instantiated.
say 'Install a block-format template'
run "echo 'service serv:%i {'                          >  $FINIT_RCSD/available/serv@.conf"
run "echo '    description = \"Template for %i\"'      >> $FINIT_RCSD/available/serv@.conf"
run "echo '    pid         = \"/run/serv-%i.pid\"'     >> $FINIT_RCSD/available/serv@.conf"
run "echo '    command     = \"serv -n -p -P /run/serv-%i.pid\"' >> $FINIT_RCSD/available/serv@.conf"
run "echo '}'                                          >> $FINIT_RCSD/available/serv@.conf"

say 'Enable two instances'
run "initctl enable serv@eth0.conf"
run "initctl enable serv@eth1.conf"
run "initctl reload"

retry 'assert_num_services 2 serv'
assert_desc "Template for eth0" serv:eth0
assert_desc "Template for eth1" serv:eth1

say 'Both instances run, each with its own instantiated PID file'
retry 'assert_num_children 2 serv'
retry 'assert_file_exists /run/serv-eth0.pid'
retry 'assert_file_exists /run/serv-eth1.pid'

# available/ is never globbed, so enabling the bare template is the
# only way the "skip the template itself" branch is reached at all.
say 'A bare template in enabled/ registers nothing'
run "ln -sf ../available/serv@.conf $FINIT_RCSD/enabled/serv@.conf"
run "initctl reload"

retry 'assert_num_services 2 serv'
run "rm -f $FINIT_RCSD/enabled/serv@.conf"

# assert_num_services cannot express "exactly one": initctl status
# prints a detail block for a single match and a table only for
# several, so the line count is 13, not 1.  Check the survivor and the
# absence of the other instead.
say 'Disable one instance'
run "initctl disable serv@eth1.conf"
run "initctl reload"

retry 'assert_num_children 1 serv'
assert_desc "Template for eth0" serv:eth0
assert_num_services 0 serv:eth1

say 'Legacy one-liner templates still instantiate'
run "echo 'service :%i pid:/run/serv-%i.pid serv -n -p -P /run/serv-%i.pid -- Legacy template for %i' > $FINIT_RCSD/available/serv@.conf"
run "initctl reload"

retry 'assert_num_children 1 serv'
assert_desc "Legacy template for eth0" serv:eth0

say 'A typo in a block template is rejected, and named after the instance'
run "echo 'service serv:%i {'                          >  $FINIT_RCSD/available/serv@.conf"
run "echo '    descriptoin = \"Template for %i\"'      >> $FINIT_RCSD/available/serv@.conf"
run "echo '    command     = \"serv -n\"'              >> $FINIT_RCSD/available/serv@.conf"
run "echo '}'                                          >> $FINIT_RCSD/available/serv@.conf"
run "initctl reload"

retry 'assert_num_children 0 serv'
assert_num_services 0 serv
