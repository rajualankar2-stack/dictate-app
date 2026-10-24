#!/usr/bin/env python3
"""Whistle server: 16.9 MB on-device STT by Cactus Compute, for the Dictate menu-bar app.

  whistle_srv.py serve [--idle SECONDS]   run in the foreground (model loads, then listens)
  whistle_srv.py start [--idle SECONDS]   run detached; idempotent
  whistle_srv.py stop                     stop the detached server (only if the pid is ours)
  whistle_srv.py status                   print running/stopped

HTTP (127.0.0.1 only):
  GET  /health      200 "ok" once the model is loaded
  POST /transcribe  body = WAV bytes (16 kHz mono preferred). 200 text/plain = the text
                    (empty text = silence or clip too short). 400 = bad audio. 500 = model error.
"""
import io, os, signal, sys, threading, time, wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT = int(os.environ.get('WHISTLE_PORT', os.environ.get('DICTATE_PORT', '8773')))
PID = HERE / 'whistle_srv.pid'
LOG = HERE / 'whistle_srv.log'
DEFAULT_IDLE = 600
MIN_SECONDS = 0.3
KEYWORDS = ["SAP", "S/4HANA", "MIGO", "MIRO", "IDoc", "EWM", "BTP", "CPI", "Fiori", "OData",
            "BRFplus", "Hermes", "OpenCode", "DeepSeek", "Moonshine", "Colab", "Telegram",
            "Claude", "Whistle", "Kokoro", "Sonnet", "NPS", "EMI", "UAT", "SIT", "DEX",
            "Zorblax", "Laya", "Zev", "Antigravity", "Remotion", "Chrome Bridge", "Three.js"]


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


def write_pid(pid):
    PID.write_text(str(pid))


def remove_pid():
    try:
        PID.unlink()
    except FileNotFoundError:
        pass


def log(msg):
    with open(LOG, 'a') as f:
        f.write(msg + '\n')


def transcribe_wav(data):
    import tempfile, os as _os
    # Whistle needs 16 kHz mono WAV; Dictate records that already.
    # Write to temp file (Whistle API takes a path).
    fd, path = tempfile.mkstemp(suffix='.wav')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        from needle.agent.whistle import transcribe
        result = transcribe(path, keywords=KEYWORDS)
        return (result.get('text') or '').strip()
    finally:
        try:
            _os.unlink(path)
        except OSError:
            pass


class Handler:
    def __init__(self, conn):
        self.conn = conn

    def handle(self):
        try:
            # Read HTTP request
            buf = b''
            while b'\r\n\r\n' not in buf:
                chunk = self.conn.recv(4096)
                if not chunk:
                    return
                buf += chunk
            headers, _, body_start = buf.partition(b'\r\n\r\n')
            lines = headers.decode('latin-1').split('\r\n')
            method, path, _ = lines[0].split(' ', 2)
            content_length = 0
            for line in lines[1:]:
                if line.lower().startswith('content-length:'):
                    content_length = int(line.split(':', 1)[1].strip())
            if content_length > 10 * 1024 * 1024:
                self._respond(413, b'body too large', 'text/plain')
                return
            # Read remaining body
            body = body_start
            while len(body) < content_length:
                chunk = self.conn.recv(4096)
                if not chunk:
                    break
                body += chunk

            if method == 'GET' and path == '/health':
                self._respond(200, b'ok', 'text/plain')
            elif method == 'POST' and path == '/transcribe':
                try:
                    text = transcribe_wav(body)
                    self._respond(200, text.encode('utf-8'), 'text/plain')
                except Exception as e:
                    log(f'error: {e}')
                    self._respond(500, str(e).encode('utf-8'), 'text/plain')
            else:
                self._respond(404, b'not found', 'text/plain')
        except Exception as e:
            log(f'handler error: {e}')
        finally:
            self.conn.close()

    def _respond(self, status, body, ctype):
        status_text = {200: 'OK', 400: 'Bad Request', 404: 'Not Found', 500: 'Internal Server Error'}.get(status, 'OK')
        resp = f'HTTP/1.1 {status} {status_text}\r\nContent-Type: {ctype}\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n'.encode() + body
        self.conn.sendall(resp)


def serve(idle_seconds):
    import socket
    log(f'starting on port {PORT}, idle={idle_seconds}')
    # Load model (warm up)
    try:
        import tempfile
        fd, path = tempfile.mkstemp(suffix='.wav')
        os.close(fd)
        # create a tiny 16k wav
        import wave as w, struct
        wf = w.open(path, 'w')
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(16000)
        for i in range(1600):
            wf.writeframes(struct.pack('<h', 0))
        wf.close()
        from needle.agent.whistle import transcribe
        transcribe(path, keywords=KEYWORDS)
        os.unlink(path)
        log('model loaded')
    except Exception as e:
        log(f'model load error: {e}')

    last_activity = [time.time()]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', PORT))
    srv.listen(8)
    srv.settimeout(1.0)

    def accept_loop():
        while True:
            try:
                conn, _ = srv.accept()
                conn.settimeout(30)
                last_activity[0] = time.time()
                t = threading.Thread(target=Handler(conn).handle, daemon=True)
                t.start()
            except socket.timeout:
                pass
            except Exception as e:
                log(f'accept error: {e}')

    t = threading.Thread(target=accept_loop, daemon=True)
    t.start()

    # Idle watchdog
    while True:
        time.sleep(5)
        if idle_seconds > 0 and time.time() - last_activity[0] > idle_seconds:
            log('idle timeout, exiting')
            break

    srv.close()
    remove_pid()


def cmd_start(idle):
    pid = read_pid()
    if pid and pid_alive(pid):
        print('already running')
        return
    # detach
    import subprocess
    with open(LOG, 'a') as lf:
        p = subprocess.Popen([sys.executable, __file__, 'serve', '--idle', str(idle)],
                             stdout=lf, stderr=lf, start_new_session=True)
    write_pid(p.pid)
    print(f'started pid {p.pid}')


def is_ours(pid):
    try:
        out = subprocess.check_output(['ps', '-o', 'command=', '-p', str(pid)], text=True, stderr=subprocess.DEVNULL).strip()
        return 'whistle_srv.py' in out
    except Exception:
        return False

def cmd_stop():
    pid = read_pid()
    if pid and pid_alive(pid) and is_ours(pid):
        os.kill(pid, signal.SIGTERM)
        print('stopped')
    else:
        print('not running (or not ours)')
    remove_pid()


def cmd_status():
    pid = read_pid()
    if pid and pid_alive(pid):
        print(f'running pid {pid}')
    else:
        print('stopped')
        remove_pid()


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    if args[0] == 'serve':
        idle = DEFAULT_IDLE
        if '--idle' in args:
            idle = int(args[args.index('--idle') + 1])
        serve(idle)
    elif args[0] == 'start':
        idle = DEFAULT_IDLE
        if '--idle' in args:
            idle = int(args[args.index('--idle') + 1])
        cmd_start(idle)
    elif args[0] == 'stop':
        cmd_stop()
    elif args[0] == 'status':
        cmd_status()
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
