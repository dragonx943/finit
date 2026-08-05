#!/bin/sh
# Verify duplicate section titles.  The title is the service identity,
# and libconfuse merges two sections that share one, silently folding
# two declarations into a single service.  A file doing that is
# rejected.  Across files the same title is still how an administrator
# overrides a system .conf, so that has to keep working.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
BOOTSTRAP="service service.sh {
    description = \"Base\"
    runlevel    = \"S12345\"
    command     = \"service.sh\"
}"

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_RCSD/dup.conf $FINIT_RCSD/override.conf"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'The service from the bootstrap file is running'
retry 'assert_num_children 1 service.sh'
assert_desc "Base" service.sh

# Written as two blocks the file used to load as one service, gated by
# whichever if came last.  Rejecting the file makes that visible.
say 'Two blocks with one title are rejected, and the file loads nothing'
run "echo 'service dupsvc {'                       >  $FINIT_RCSD/dup.conf"
run "echo '    if      = \"service.sh\"'           >> $FINIT_RCSD/dup.conf"
run "echo '    command = \"serv -np -i dupsvc\"'   >> $FINIT_RCSD/dup.conf"
run "echo '}'                                      >> $FINIT_RCSD/dup.conf"
run "echo 'service dupsvc {'                       >> $FINIT_RCSD/dup.conf"
run "echo '    if      = \"nosuchservice\"'        >> $FINIT_RCSD/dup.conf"
run "echo '    command = \"serv -np -i dupsvc\"'   >> $FINIT_RCSD/dup.conf"
run "echo '}'                                      >> $FINIT_RCSD/dup.conf"
run "initctl reload"

assert_loaded dupsvc 0

# A rejected file must not reach the legacy parser either, and the
# rest of the configuration has to survive it.
say 'The other .conf files are unaffected'
retry 'assert_num_children 1 service.sh'
assert_desc "Base" service.sh

# Detection of the format has to stay syntactic for this: a probe that
# answers "not block format" on a duplicate title would hand the file
# to the legacy parser, which registers a bogus service per line.
say 'A distinct title in the same file loads as its own service'
run "rm -f $FINIT_RCSD/dup.conf"
run "echo 'service dupsvc:1 {'                     >  $FINIT_RCSD/dup.conf"
run "echo '    command = \"serv -np -i dupsvc1\"'  >> $FINIT_RCSD/dup.conf"
run "echo '}'                                      >> $FINIT_RCSD/dup.conf"
run "echo 'service dupsvc:2 {'                     >> $FINIT_RCSD/dup.conf"
run "echo '    command = \"serv -np -i dupsvc2\"'  >> $FINIT_RCSD/dup.conf"
run "echo '}'                                      >> $FINIT_RCSD/dup.conf"
run "initctl reload"

retry 'assert_loaded dupsvc:1 1'
assert_loaded dupsvc:2 1

# finit.d is read after finit.conf, so the later declaration of the
# same identity replaces the earlier one.  This is the override path,
# and it is a different file, so no duplicate title is involved.
say 'The same title in another file overrides, it does not conflict'
run "echo 'service service.sh {'                   >  $FINIT_RCSD/override.conf"
run "echo '    description = \"Override\"'         >> $FINIT_RCSD/override.conf"
run "echo '    command     = \"service.sh\"'       >> $FINIT_RCSD/override.conf"
run "echo '}'                                      >> $FINIT_RCSD/override.conf"
run "initctl reload"

retry 'assert_desc "Override" service.sh'
assert_num_children 1 service.sh
