#!/bin/bash
# Silent live test of the right-Option long press on the REAL Dictate.app. Plays no sound.
# A request reaching the server (log line "transcribed" or "skipped") proves: key events -> detector -> recorder -> server.
# A server that is not running proves recording never started (the app starts it on key down).
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PY=~/Sandbox/experiments/moonshine-stt/.venv/bin/python; E="env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV"
scripts/build_harness.sh >/dev/null
swiftc -O -o /tmp/gui_driver scripts/gui_harness.swift 2>&1 | grep error
pgrep -f "Dictate.app/Contents/MacOS/Dictate$" >/dev/null || { open -n -g build/Dictate.app; sleep 4; }
rm -f /tmp/gh_target.json; open -n --stdout /tmp/gh_target.json /tmp/GuiHarness.app --args target 120; sleep 2
FAIL=0
run() {  # name side hold letterAt expect(request|none)
  $E $PY server/dictate_srv.py stop >/dev/null; sleep 2; : > server/dictate_srv.log
  /tmp/gui_driver optdriver "$2" "$3" "${4:--1}" >/dev/null
  if [ "$5" = "request" ]; then
    for i in $(seq 1 25); do grep -a -q -E "transcribed|skipped" server/dictate_srv.log && break; sleep 1; done
  else sleep 8; fi
  if grep -a -q -E "transcribed|skipped" server/dictate_srv.log; then got=request; else got=none; fi
  srv=$($E $PY server/dictate_srv.py status)
  if [ "$got" = "$5" ]; then r=PASS; else r=FAIL; FAIL=1; fi
  echo "$r  $1: expected $5, got $got (server: $srv)"
}
run "A hold right Option 1.5 s"                  right 1.5 -1  request
run "B quick tap 0.1 s"                           right 0.1 -1  none
run "C Option+A within 0.1 s (modifier use)"     right 1.5 0.1 none
run "D hold LEFT Option 1.5 s"                   left  1.5 -1  none
run "E letter pressed AFTER recording began"     right 1.5 0.9 request
run "F tap 0.25 s (just under the 0.3 s limit)"  right 0.25 -1 none
run "G hold right Option 1.5 s again"            right 1.5 -1  request
$E $PY server/dictate_srv.py stop >/dev/null
pkill -f "GuiHarness.app/Contents/MacOS/GuiHarness"; rm -rf /tmp/GuiHarness.app /tmp/gui_driver /tmp/gh_target.json
echo "failures: $FAIL"
