#!/usr/bin/env python3
"""Dictation server: Whisper-small + Raj's LoRA adapter, for the Dictate menu-bar app.

  dictate_srv.py serve [--idle SECONDS]   run in the foreground (model loads, then listens)
  dictate_srv.py start [--idle SECONDS]   run detached; idempotent
  dictate_srv.py stop                     stop the detached server (only if the pid is ours)
  dictate_srv.py status                   print running/stopped

HTTP (127.0.0.1 only):
  GET  /health      200 "ok" once the model is loaded
  POST /transcribe  body = WAV bytes (any rate, mono or stereo). 200 text/plain = the text
                    (empty text = silence or clip too short). 400 = bad audio. 500 = model error.

Differences from Hermes's whisper_srv.py (which stays untouched on port 8771):
  - the SAP word fixes run in the server
  - audio is converted to 16 kHz mono here, so any WAV is accepted
  - clips over 28 s are cut at the quietest point and joined (Whisper reads 30 s at most)
  - silence returns empty text (Whisper invents "Thank you." on silence)
  - errors use HTTP status codes
  - the server exits after IDLE seconds without a /transcribe call (frees about 2 GB)
"""
import io, os, re, signal, subprocess, sys, threading, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT = int(os.environ.get('DICTATE_PORT', '8772'))
PID = HERE / 'dictate_srv.pid'
LOG = HERE / 'dictate_srv.log'
BASE = 'openai/whisper-small'
ADAPTER = os.path.expanduser(os.environ.get('DICTATE_ADAPTER', '~/Sandbox/experiments/moonshine-ft/adapter_v2/test'))
DEFAULT_IDLE = 600
MIN_SECONDS = 0.3
SILENCE_RMS = 0.002
CHUNK_MAX = 28.0
CHUNK_MIN = 15.0
MAX_VOCAB = 30
MAX_PROMPT_TOKENS = 190   # Whisper allows 223 prompt tokens; 190 + 200 new tokens fits the 448-token decoder window
PROMPT = ("SAP, S/4HANA, MIGO, MIRO, IDoc, EWM, BTP, CPI, Fiori, OData, BRFplus, Hermes, OpenCode, DeepSeek, "
          "Moonshine, Colab, Telegram, Claude, Whistle, Kokoro, Sonnet, NPS, EMI, UAT, SIT, DEX, Froggy's blog, "
          "Laya, Zev, Antigravity, Remotion, Chrome Bridge, Three.js")

# (pattern, replacement, flags). Anchor a rule when the bare form is an ordinary word.
I = re.I
FIXES = [
    (r"\bopen ?code\b", "OpenCode", I),
    (r"\bdeep ?seek\b", "DeepSeek", I),
    (r"\bmoon ?shine\b", "Moonshine", I),
    (r"(?<=\bsap )(?:my ?go|me ?go)\b", "MIGO", I),
    (r"\bmigo\b", "MIGO", I),
    (r"\bmiro\b", "MIRO", I),
    (r"\bi[ -]?docs?\b", lambda m: "IDocs" if m.group(0).lower().endswith("s") else "IDoc", I),
    (r"\bs[\s/-]*(?:slash[\s/-]*)?(?:4|for|four)[\s-]*hana\b", "S/4HANA", I),
    (r"\bfiori\b", "Fiori", I),
    (r"\bodata\b", "OData", I),
    (r"\bbtp\b", "BTP", I),
    (r"\bbrf ?plus\b", "BRFplus", I),
    (r"\bcloud (?=(?:code|sonnet|opus|haiku|max)\b)", "Claude ", I),
    (r"\bEPI\b", "API", 0),
]


def fix(text):
    for pat, rep, flags in FIXES:
        text = re.sub(pat, rep, text, flags=flags)
    return text


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
    return 'dictate_srv.py' in out


def cmd_stop():
    pid = read_pid()
    if pid is None:
        print('no pid file'); return 0
    if pid_alive(pid) and is_ours(pid):
        os.kill(pid, signal.SIGTERM); print('stopped', pid)
    else:
        print('pid not ours or not running; not killed')
    return 0


def cmd_start(idle):
    import fcntl
    # One start at a time: two racing starts must not leave the pid file pointing at the loser.
    with open(HERE / 'dictate_srv.lock', 'w') as lk:
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


def cmd_status():
    pid = read_pid()
    print('running' if pid and pid_alive(pid) and is_ours(pid) else 'stopped')
    return 0


def parse_vocabulary(header):
    """X-Vocabulary: comma-separated, each term percent-encoded. Returns clean terms; never raises."""
    from urllib.parse import unquote
    out, seen = [], set()
    for part in (header or '').split(','):
        if not re.fullmatch(r'(?:[A-Za-z0-9._~-]|%[0-9A-Fa-f]{2})*', part):
            continue   # not something the app would send: a stray % or raw symbol
        try:
            t = unquote(part, errors='strict').strip()
        except Exception:
            continue
        if not t or len(t) > 40 or any(ord(ch) < 32 for ch in t) or t.lower() in seen:
            continue
        seen.add(t.lower()); out.append(t)
        if len(out) == MAX_VOCAB:
            break
    return out


def prepare_audio(raw):
    """WAV bytes -> float32 mono 16 kHz numpy array. Raises ValueError on unreadable audio."""
    import numpy as np, soundfile as sf
    from math import gcd
    from scipy.signal import resample_poly
    try:
        w, sr = sf.read(io.BytesIO(raw), dtype='float32', always_2d=True)
    except Exception as e:
        raise ValueError(f'unreadable audio: {e}')
    if w.shape[0] == 0:
        raise ValueError('empty audio')
    w = w.mean(axis=1)
    if sr != 16000:
        g = gcd(16000, int(sr))
        w = resample_poly(w, 16000 // g, int(sr) // g).astype('float32')
    return np.ascontiguousarray(w, dtype='float32')


def split_points(w, sr=16000):
    """Cut points so no piece exceeds CHUNK_MAX; each cut sits at the quietest 100 ms window
    between CHUNK_MIN and CHUNK_MAX seconds after the piece start."""
    import numpy as np
    cuts, start, win = [], 0, sr // 10
    while len(w) - start > CHUNK_MAX * sr:
        lo, hi = start + int(CHUNK_MIN * sr), start + int(CHUNK_MAX * sr)
        seg = w[lo:hi]
        n = (len(seg) // win) * win
        energy = (seg[:n].reshape(-1, win) ** 2).mean(axis=1)
        cut = lo + int(np.argmin(energy)) * win + win // 2
        cuts.append(cut)
        start = cut
    return cuts


def serve(idle):
    import numpy as np, torch
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    t0 = time.time()
    proc = WhisperProcessor.from_pretrained(BASE, language='en', task='transcribe')
    base = WhisperForConditionalGeneration.from_pretrained(BASE).eval()
    if os.path.isdir(ADAPTER):
        from peft import PeftModel
        model = PeftModel.from_pretrained(base, ADAPTER).eval()
        print(f'loaded with adapter={ADAPTER}', flush=True)
    else:
        model = base
        print('loaded base model (no adapter)', flush=True)
    prompt_ids = proc.tokenizer.get_prompt_ids(PROMPT, return_tensors='pt')
    prompt_cache = {(): prompt_ids}
    lock = threading.Lock()
    state = {'last': time.time()}
    print(f'loaded in {time.time() - t0:.1f}s adapter={ADAPTER}', flush=True)

    def prompt_for(extra):
        """Base prompt plus the user's terms. Terms are dropped from the end until it fits Whisper's prompt window."""
        key = tuple(extra)
        if key in prompt_cache:
            return prompt_cache[key]
        terms = list(extra)
        while True:
            text = PROMPT + (', ' + ', '.join(terms) if terms else '')
            ids = proc.tokenizer.get_prompt_ids(text, return_tensors='pt')
            if ids.shape[-1] <= MAX_PROMPT_TOKENS or not terms:
                break
            terms.pop()
        if len(prompt_cache) > 20:
            prompt_cache.clear(); prompt_cache[()] = prompt_ids
        prompt_cache[key] = ids
        return ids

    def run_piece(piece, ids):
        feats = proc.feature_extractor(piece, sampling_rate=16000, return_tensors='pt').input_features
        with torch.no_grad():
            out = model.generate(feats, max_new_tokens=200, prompt_ids=ids, language='en', task='transcribe')
        return proc.batch_decode(out, skip_special_tokens=True)[0].strip()

    def transcribe(raw, extra=()):
        w = prepare_audio(raw)
        rms = float(np.sqrt((w ** 2).mean()))
        if len(w) / 16000 < MIN_SECONDS:
            print(f'skipped: too short ({len(w) / 16000:.2f}s)', flush=True)
            return ''
        if rms < SILENCE_RMS:
            print(f'skipped: silent (dur={len(w) / 16000:.1f}s rms={rms:.5f}, threshold {SILENCE_RMS})', flush=True)
            return ''
        cuts = split_points(w)
        bounds = [0] + cuts + [len(w)]
        parts = []
        with lock:
            ids = prompt_for(extra)   # inside the lock: the prompt cache is shared between request threads
            for a, b in zip(bounds, bounds[1:]):
                parts.append(run_piece(w[a:b], ids))
        text = ' '.join(p for p in parts if p)
        # Whisper's prompt text can leak into the output on near-silent pieces; drop it if it did
        if text.startswith(PROMPT[:40]):
            return ''
        return fix(text).strip()

    class H(BaseHTTPRequestHandler):
        def _send(self, code, body, ctype='text/plain; charset=utf-8', extra=None):
            data = body.encode()
            self.send_response(code)
            self.send_header('content-type', ctype)
            self.send_header('content-length', str(len(data)))
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path, _, query = self.path.partition('?')
            if path == '/health':
                # ?touch=1 counts as activity: the app sends it when a key goes down, so the idle timer
                # cannot expire while the user is speaking. A plain /health (monitors) does not.
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
                text = transcribe(raw, parse_vocabulary(self.headers.get('x-vocabulary')))
            except ValueError as e:
                self._send(400, str(e)); print('bad audio', e, flush=True); return
            except Exception as e:
                self._send(500, f'model error: {e!r}'); print('error', repr(e), flush=True); return
            state['last'] = time.time()
            self._send(200, text, extra={'x-elapsed': f'{time.time() - t:.3f}'})
            print(f'transcribed {time.time() - t:.2f}s {len(text)} chars', flush=True)

        def log_message(self, *a):
            pass

    try:
        srv = ThreadingHTTPServer(('127.0.0.1', PORT), H)
    except OSError as e:
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
    srv.serve_forever()
    srv.server_close()
    try:
        if read_pid() == os.getpid():
            PID.unlink()
    except Exception:
        pass
    print('exited cleanly', flush=True)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'start'
    idle = DEFAULT_IDLE
    if '--idle' in argv:
        idle = int(argv[argv.index('--idle') + 1])
    if cmd == 'serve':
        serve(idle); return 0
    if cmd == 'start':
        return cmd_start(idle)
    if cmd == 'stop':
        return cmd_stop()
    if cmd == 'status':
        return cmd_status()
    print(__doc__); return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
