#!/bin/bash
# Full re-verification. Output: tests-data/final_run.log
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PY=~/Sandbox/experiments/moonshine-stt/.venv/bin/python
E="env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV"
L=tests-data/final_run.log
: > $L
{
echo "##### swift unit tests"
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | sort -u
echo "##### integration test (real server)"
DICTATE_INTEGRATION=1 swift test --filter IntegrationTests 2>&1 | grep -E "cold:|warm:|error:|Executed 1 test" | sort -u
sleep 3; pgrep -fl dictate_srv.py || echo "no server left"
echo "##### build + sign app"
scripts/build_app.sh 2>&1 | tail -4
echo "##### server test suite"
$E $PY server/test_server.py 2>&1 | grep -v -E "NOTE|Both .max_new|Using custom|Transcription using"
echo "##### soak + 30 real held-out clips (English forced)"
$E $PY server/dictate_srv.py start
for i in $(seq 1 60); do curl -s -m 1 http://127.0.0.1:8772/health | grep -q ok && break; sleep 1; done
$E $PY ~/.hermes/cache/scratch/soak_real.py 2>&1 | grep -v -E "NOTE|Both .max_new|Using custom|Transcription using"
$E $PY server/dictate_srv.py stop; sleep 3
echo "##### process scenarios"
$E scripts/scenarios.sh 2>&1 | grep -v -E "NOTE|Both .max_new|Using custom|Transcription using"
echo "##### leftovers"
pgrep -fl dictate_srv.py || echo "no dictate server running"
lsof -nP -iTCP:8772 -sTCP:LISTEN | tail -1 || true
echo "##### DONE"
} >> $L 2>&1
