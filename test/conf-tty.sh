#!/bin/sh
# Verify tty block settings that have no equivalent elsewhere.  The
# 'passenv' flag is handed to the built-in getty as -p, which it turns
# into 'login -p', passing the environment on to the login program.
set -eu

TEST_DIR=$(dirname "$0")

# shellcheck disable=SC2034
BOOTSTRAP="tty console {
    runlevel = \"12345\"
    device   = \"/dev/console\"
    passenv  = true
    noclear  = true
}"

# The built-in getty is exec'd with -p ahead of the device, so the flag
# is visible in the command Finit registered.
assert_cmd_has()
{
    assert "Command of $1 contains '$2'" \
	   "$(texec initctl status "$1" | grep 'Command' | grep -c -- "$2")" -eq 1
}

test_teardown()
{
    say "Running test teardown."
    run "rm -f $FINIT_CONF"
}

# shellcheck source=/dev/null
. "$TEST_DIR/lib/setup.sh"

say 'The tty block loaded, so passenv is a known setting'
retry 'assert_loaded tty:console 1'

say 'passenv reaches the built-in getty as -p'
assert_cmd_has tty:console " -p"

say 'Waiting for bootstrap to finish before rewriting the configuration'
retry "test \"\$(texec sh -c \"initctl runlevel | awk '{print \\\$2;}'\")\" = 2" 20 1

say 'Without passenv the flag is absent'
run "echo 'tty console {'                    >  $FINIT_CONF"
run "echo '    runlevel = \"12345\"'         >> $FINIT_CONF"
run "echo '    device   = \"/dev/console\"'  >> $FINIT_CONF"
run "echo '    noclear  = true'              >> $FINIT_CONF"
run "echo '}'                                >> $FINIT_CONF"
run "initctl reload"

retry 'assert_loaded tty:console 1'
assert "Command has no -p" \
       "$(texec initctl status tty:console | grep 'Command' | grep -c -- ' -p')" -eq 0

# passenv is a built-in getty flag.  An external getty takes its
# arguments from command, so there is nowhere to put it, and the
# setting is refused rather than silently dropped.  Note the device
# still has to be in there: an external getty is told which TTY to
# open by its own arguments, and that is also where Finit reads it
# from to name the service.
say 'passenv with an external getty is refused, the tty still loads'
run "echo 'tty extgetty {'                             >  $FINIT_CONF"
run "echo '    runlevel = \"12345\"'                   >> $FINIT_CONF"
run "echo '    command  = \"/bin/sh /dev/console\"'    >> $FINIT_CONF"
run "echo '    passenv  = true'                        >> $FINIT_CONF"
run "echo '}'                                          >> $FINIT_CONF"
run "initctl reload"

retry 'assert_loaded tty:console 1'
assert "external getty command has no -p" \
       "$(texec initctl status tty:console | grep 'Command' | grep -c -- ' -p')" -eq 0
