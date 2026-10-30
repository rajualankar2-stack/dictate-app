#!/bin/bash
# Does loading the server while the user speaks hurt the recording?  usage: tone_test.sh warm|cold
# Presses the real hotkey, plays a steady 6 s tone for the mic, saves what the server received (test-only), prints dB per 0.5 s.
cd "$(dirname "$0")/.."
MODE="${1:-warm}"
PY=~/Sandbox/experiments/moonshine-stt/.venv/bin/python; E="env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV"
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=1000:duration=6" -ar 44100 -ac 2 /tmp/tone.wav
OUTV=$(osascript -e 'output volume of (get volume settings)'); INV=$(osascript -e 'input volume of (get volume settings)')
restore() { osascript -e "set volume output volume $OUTV" -e "set volume input volume $INV" >/dev/null 2>&1; rm -f /tmp/tone.wav /tmp/dictate_dbg.wav; }
trap restore EXIT
$E $PY server/parakeet_srv.py stop >/dev/null; sleep 2
export DICTATE_DEBUG_SAVE=/tmp/dictate_dbg.wav; rm -f $DICTATE_DEBUG_SAVE
if [ "$MODE" = "warm" ]; then
  $E $PY server/parakeet_srv.py start >/dev/null
  for i in $(seq 1 60); do curl -s -m 1 http://127.0.0.1:8774/health | grep -q ok && break; sleep 1; done
  # warm the model fully with one throwaway request
  curl -s -m 60 --data-binary @tests-data/plain1.wav http://127.0.0.1:8774/transcribe >/dev/null
fi
: > server/parakeet_srv.log
pgrep -f "Dictate.app/Contents/MacOS/Dictate$" >/dev/null || { open -n -g build/Dictate.app; sleep 4; }
# the app starts its OWN server in cold mode: it must see our debug env, so launch via the script's server for cold too
if [ "$MODE" = "cold" ]; then
  : # cold: the server is started right before the key press (below), so the model loads while the user is speaking
fi
osascript -e 'set volume output volume 85' -e 'set volume input volume 70' >/dev/null
rm -f /tmp/gh_target.json; open -n --stdout /tmp/gh_target.json /tmp/GuiHarness.app --args target 12; sleep 1.5
if [ "$MODE" = "cold" ]; then $E $PY server/parakeet_srv.py start >/dev/null; sleep 0.3; fi
/tmp/gui_driver driver 7.5 "afplay:/tmp/tone.wav" > /tmp/gh_driver.json
sleep 6
pkill -f "GuiHarness.app/Contents/MacOS/GuiHarness" 2>/dev/null
echo "mode=$MODE  server log: $(grep -a -E 'loaded|transcribed|skipped' server/parakeet_srv.log | tr '\n' '|')"
if [ -f /tmp/dictate_dbg.wav ]; then
  ffmpeg -hide_banner -i /tmp/dictate_dbg.wav -af "asetnsamples=n=8000,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level" -f null - 2>&1 | grep RMS_level | awk -F= '{printf "%.0f ", $2} END {print "(dB per 0.5 s)"}'
else
  echo "(no saved audio in this mode)"
fi
$E $PY server/parakeet_srv.py stop >/dev/null
