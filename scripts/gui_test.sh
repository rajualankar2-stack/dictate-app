#!/bin/bash
# Live end-to-end test of the REAL Dictate.app: hotkey -> microphone -> server -> paste into a window.
# usage: gui_test.sh "<sentence to speak>" [voice] [hold-seconds]
# Needs: Dictate.app permissions granted, Mac unlocked. Temporarily raises output/input volume, then restores them.
cd "$(dirname "$0")/.."
SENT="${1:-Post the goods receipt in MIGO and then check the invoice in MIRO.}"
VOICE="${2:-Rishi}"; HOLD="${3:-7}"
OUTV=$(osascript -e 'output volume of (get volume settings)'); INV=$(osascript -e 'input volume of (get volume settings)')
restore() { osascript -e "set volume output volume $OUTV" -e "set volume input volume $INV" >/dev/null 2>&1; }
trap restore EXIT
osascript -e 'set volume output volume 85' -e 'set volume input volume 70' >/dev/null 2>&1
pgrep -f "Dictate.app/Contents/MacOS/Dictate$" >/dev/null || { open -n -g build/Dictate.app; sleep 4; }
: > server/dictate_srv.log
rm -f /tmp/gh_target.json
open -n --stdout /tmp/gh_target.json /tmp/GuiHarness.app --args target 45
sleep 2.5
/tmp/gui_driver driver "$HOLD" "$SENT" "$VOICE" > /tmp/gh_driver.json
for i in $(seq 1 60); do grep -q textAppearedEpoch /tmp/gh_target.json 2>/dev/null && break; sleep 1; done
python3 - <<'EOF'
import json
d = json.load(open('/tmp/gh_driver.json')); t = json.load(open('/tmp/gh_target.json'))
print('frontmost app when target started:', t['frontmostAtStart'])
print('driver has Accessibility:', d['AXTrusted'])
print('text pasted:', repr(t['text']))
print('timed out:', t['timedOut'])
print('seconds from key release to text: %.2f' % (t['textAppearedEpoch'] - d['releasedEpoch']))
print('clipboard restored to the earlier content:', t['clipboardRestored'])
EOF
echo "--- server log (numbers only)"; grep -a -E "loaded|transcribed|skipped|error|bad audio" server/dictate_srv.log | tail -5
