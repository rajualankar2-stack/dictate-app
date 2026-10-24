#!/bin/bash
# Process-level scenarios against the real app binary and real server. Never touches the real config.
cd "$(dirname "$0")/.."
B=build/Dictate.app/Contents/MacOS/Dictate
PY=~/Sandbox/experiments/moonshine-stt/.venv/bin/python
SRV="$PY server/dictate_srv.py"
W=$(mktemp -d)
export DICTATE_CONFIG=$W/config.json
j() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print({k:(round(v,1) if isinstance(v,float) else v) for k,v in d.items()})"; }

echo "== A. idle shutdown, then restart on next use (idle=6s)"
echo '{"idleSeconds": 6}' > $DICTATE_CONFIG
$B --selftest-transcribe tests-data/plain1.wav | j
sleep 13
echo "server after idle: $($SRV status)"; lsof -nP -iTCP:8772 -sTCP:LISTEN | tail -1
$B --selftest-transcribe tests-data/plain1.wav | j
$SRV stop; sleep 2

echo "== B. kill -9 the server, stale pid file left behind, next use recovers"
echo '{"idleSeconds": 600}' > $DICTATE_CONFIG
$B --selftest-transcribe tests-data/plain1.wav | j
PID=$(cat server/dictate_srv.pid); kill -9 $PID; sleep 1
echo "pid file still says $(cat server/dictate_srv.pid); process alive? $(kill -0 $PID 2>&1 | head -1)"
$B --selftest-transcribe tests-data/sap1.wav | j
$SRV stop; sleep 2

echo "== C. port 8772 held by another program: must fail fast with a clear message"
mkdir -p $W/www; cd $W/www; python3 -m http.server 8772 --bind 127.0.0.1 >/dev/null 2>&1 &
DUMMY=$!; cd - >/dev/null
sleep 1
T0=$(date +%s)
$B --selftest-transcribe tests-data/plain1.wav | j
echo "took $(( $(date +%s) - T0 )) s"
kill $DUMMY 2>/dev/null; sleep 1
lsof -nP -iTCP:8772 -sTCP:LISTEN | tail -1; echo "(port released if nothing above)"

echo "== D. python path wrong: immediate clear error"
echo '{"pythonPath": "/nonexistent/python"}' > $DICTATE_CONFIG
$B --selftest-transcribe tests-data/plain1.wav | j

echo "== E. config.json broken: warning, defaults still work"
echo '{oops' > $DICTATE_CONFIG
$B --selftest-status | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('configWarning:', d['configWarning'])"

echo "== cleanup check"
$SRV status; pgrep -fl "http.server 8772" || echo "no dummy server left"; rm -rf $W
