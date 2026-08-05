#!/bin/sh
# Verify the block format 'if' setting: a value with a namespace
# separator is a condition, checked at runtime, anything else is a
# service name, checked when the .conf is read.  The two cannot be
# combined, and the legacy angle brackets are rejected.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
BOOTSTRAP="service anchor {
    runlevel = \"S12345\"
    command  = \"serv -np -i anchor\"
}
service byname {
    runlevel = \"S12345\"
    if       = \"anchor\"
    command  = \"serv -np -i byname\"
}
service noname {
    runlevel = \"S12345\"
    if       = \"nosuchservice\"
    command  = \"serv -np -i noname\"
}
service negated {
    runlevel = \"S12345\"
    if       = \"!anchor\"
    command  = \"serv -np -i negated\"
}
service bycond {
    runlevel = \"S12345\"
    if       = \"usr/enable-me\"
    command  = \"serv -np -i bycond\"
}
service brackets {
    runlevel = \"S12345\"
    if       = \"<usr/enable-me>\"
    command  = \"serv -np -i brackets\"
}
service mixed {
    runlevel = \"S12345\"
    if       = \"anchor,usr/enable-me\"
    command  = \"serv -np -i mixed\"
}"

test_teardown()
{
    say "Running test teardown."
    run "initctl cond clear enable-me" || true
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'A bare value names a service, resolved when the .conf is read'
retry 'assert_loaded byname 1'

say 'A service that is not known keeps the block out of the config'
assert_loaded noname 0

say 'Negation of a known service keeps the block out too'
assert_loaded negated 0

say 'A value with a namespace separator is a condition, so the block is'
say 'loaded, but held until the condition is asserted'
assert_loaded bycond 1
assert_status bycond halted

run "initctl cond set enable-me"
retry 'assert_status bycond running'

# 'if' qualifies the block, it does not track the condition, so
# clearing it does not stop a running service.  The qualification is
# re-read when the configuration is, i.e. on reload.
run "initctl cond clear enable-me"
run "initctl reload"
retry 'assert_status bycond halted'

say 'Angle brackets belong to the line-based format, the block is rejected'
assert_loaded brackets 0

say 'A service name and a condition are checked at different times, so'
say 'mixing them in one statement is rejected'
assert_loaded mixed 0

say 'Rejecting a block leaves the rest of the file alone'
assert_loaded anchor 1
