#!/usr/bin/env python3
"""Parakeet server: on-device Parakeet model, for the Dictate menu-bar app.

  parakeet_srv.py serve [--idle SECONDS]   run in the foreground (engine connects, then listens)
  parakeet_srv.py start [--idle SECONDS]   run detached; idempotent
  parakeet_srv.py stop                     stop the detached server (only if the pid is ours)
  parakeet_srv.py status                   print running/stopped

Same HTTP contract as whistle_srv.py (127.0.0.1 only):
  GET  /health      200 "ok" once the engine is ready
  POST /transcribe  body = WAV bytes. 200 text/plain = the text (empty = silence or too short).

The speech engine is NVIDIA Parakeet TDT 0.6B v3 on Apple MLX (package parakeet-mlx), loaded in this
process. The first run downloads the model (about 2.5 GB) from Hugging Face; later runs work offline.
The SAP word fixes, silence guard and 16 kHz conversion come from stt_common.py.
X-Vocabulary is accepted but not used: Parakeet has no vocabulary input.
"""
import io, json, os, signal, subprocess, sys, threading, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from stt_common import fix, prepare_audio, MIN_SECONDS, SILENCE_RMS   # noqa: E402

PORT = int(os.environ.get('PARAKEET_PORT', os.environ.get('DICTATE_PORT', '8774')))
PID = HERE / 'parakeet_srv.pid'
LOG = HERE / 'parakeet_srv.log'
MODEL = os.environ.get('DICTATE_PARAKEET_MODEL', 'mlx-community/parakeet-tdt-0.6b-v3')
DEFAULT_IDLE = 600


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_pid():
    try:
        return int(PID.read_text().strip())
    except Exception:
        return None


def is_ours(pid):
    out = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
    return 'parakeet_srv.py' in out


class Engine:
    """NVIDIA Parakeet TDT 0.6B v3 on Apple MLX (package parakeet-mlx), loaded in this process.

    MLX streams belong to one thread, so one worker thread loads the model and runs every request."""

    def __init__(self):
        import queue
        self.model = None
        self.source = 'parakeet-mlx'
        self.jobs = queue.Queue()
        self.error = None
        self.ready = threading.Event()
        threading.Thread(target=self._worker, daemon=True).start()

    def _worker(self):
        try:
            from parakeet_mlx import from_pretrained   # downloads the model on the first run
            self.model = from_pretrained(MODEL)
        except BaseException as e:
            self.error = e
        self.ready.set()
        while self.error is None:
            wav_bytes, box, done = self.jobs.get()
            try:
                import tempfile
                with tempfile.NamedTemporaryFile(suffix='.wav') as f:
                    f.write(wav_bytes); f.flush()
                    box.append(self.model.transcribe(f.name).text)
            except BaseException as e:
                box.append(e)
            done.set()

    def connect(self):
        self.ready.wait()
        if self.error is not None:
            raise RuntimeError(f'Parakeet model failed to load: {self.error!r}')

    def transcribe(self, wav_bytes):
        box, done = [], threading.Event()
        self.jobs.put((wav_bytes, box, done))
        done.wait()
        if isinstance(box[0], BaseException):
            raise box[0]
        return box[0]

    def close(self):
        pass


def to_wav16(w):
    import soundfile as sf
    buf = io.BytesIO()
    sf.write(buf, w, 16000, format='WAV', subtype='PCM_16')
    return buf.getvalue()


def serve(idle):
    import numpy as np
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    t0 = time.time()
    engine = Engine()
    engine.connect()
    lock = threading.Lock()
    state = {'last': time.time()}
    print(f'ready in {time.time() - t0:.1f}s via {engine.source}, model {MODEL}', flush=True)

    def transcribe(raw):
        w = prepare_audio(raw)
        if len(w) / 16000 < MIN_SECONDS:
            return ''
        if float(np.sqrt((w ** 2).mean())) < SILENCE_RMS:
            return ''
        with lock:
            text = engine.transcribe(to_wav16(w))
        return fix(text).strip()

    class H(BaseHTTPRequestHandler):
        def _send(self, code, body, extra=None):
            data = body.encode()
            self.send_response(code)
            self.send_header('content-type', 'text/plain; charset=utf-8')
            self.send_header('content-length', str(len(data)))
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path, _, query = self.path.partition('?')
            if path == '/health':
                if 'touch=1' in query:
                    state['last'] = time.time()
                self._send(200, 'ok')
            else:
                self._send(404, 'not found')

        def do_POST(self):
            if self.path != '/transcribe':
                self._send(404, 'not found'); return
            state['last'] = time.time()
            try:
                n = int(self.headers.get('content-length', 0))
            except ValueError:
                n = 0
            if n <= 0:
                self._send(400, 'empty body'); return
            if n > 10 * 1024 * 1024:
                self._send(413, 'body too large'); return
            raw = self.rfile.read(n)
            t = time.time()
            try:
                text = transcribe(raw)
            except ValueError as e:
                self._send(400, str(e)); print('bad audio', e, flush=True); return
            except Exception as e:
                self._send(500, f'engine error: {e!r}'); print('error', repr(e), flush=True); return
            state['last'] = time.time()
            self._send(200, text, extra={'x-elapsed': f'{time.time() - t:.3f}'})
            print(f'transcribed {time.time() - t:.2f}s {len(text)} chars', flush=True)

        def log_message(self, *a):
            pass

    try:
        srv = ThreadingHTTPServer(('127.0.0.1', PORT), H)
    except OSError as e:
        engine.close()
        raise SystemExit(f'port {PORT} busy: {e}')
    srv.daemon_threads = True

    def watchdog():
        while True:
            time.sleep(2)
            if idle > 0 and time.time() - state['last'] > idle:
                print(f'idle for {idle}s; shutting down', flush=True)
                srv.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=srv.shutdown, daemon=True).start())
    print('listening', PORT, flush=True)
    try:
        srv.serve_forever()
    finally:
        srv.server_close()
        engine.close()
        try:
            if read_pid() == os.getpid():
                PID.unlink()
        except Exception:
            pass
        print('exited cleanly', flush=True)


def cmd_start(idle):
    import fcntl
    with open(HERE / 'parakeet_srv.lock', 'w') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        pid = read_pid()
        if pid and pid_alive(pid) and is_ours(pid):
            print('already running', pid); return 0
        p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), 'serve', '--idle', str(idle)],
                             stdout=open(LOG, 'a'), stderr=subprocess.STDOUT, start_new_session=True,
                             stdin=subprocess.DEVNULL)
        PID.write_text(str(p.pid))
        print('started', p.pid)
        return 0


def cmd_stop():
    pid = read_pid()
    if pid and pid_alive(pid) and is_ours(pid):
        os.kill(pid, signal.SIGTERM); print('stopped', pid)
    else:
        print('pid not ours or not running; not killed')
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'start'
    idle = int(argv[argv.index('--idle') + 1]) if '--idle' in argv else DEFAULT_IDLE
    if cmd == 'serve':
        serve(idle); return 0
    if cmd == 'start':
        return cmd_start(idle)
    if cmd == 'stop':
        return cmd_stop()
    if cmd == 'status':
        print('running' if (p := read_pid()) and pid_alive(p) and is_ours(p) else 'stopped'); return 0
    print(__doc__); return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
