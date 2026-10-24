#!/usr/bin/env python3
"""Server tests. Run with the model venv python:  test_server.py [--skip-model]
Starts its own server on port 8772 (never touches Hermes's 8771). Prints PASS/FAIL per check and a JSON summary."""
import json, os, re, signal, subprocess, sys, threading, time, urllib.request, urllib.error
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DATA = ROOT / 'tests-data'
SRV = HERE / 'dictate_srv.py'
PORT = int(os.environ.get('DICTATE_PORT', '8772'))
URL = f'http://127.0.0.1:{PORT}'
sys.path.insert(0, str(HERE))
results = []


def check(name, ok, detail=''):
    results.append({'name': name, 'ok': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if detail != '' else ''), flush=True)


def norm(t):
    t = t.lower().replace('s/4hana', 's four hana').replace('s/4 hana', 's four hana')
    t = re.sub(r'[^a-z0-9 ]', ' ', t)
    return t.split()


def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, p + (r[i - 1] != h[j - 1]))
            p = cur
    return d[len(h)] / max(1, len(r))


def post(path, body, timeout=120, headers=None):
    req = urllib.request.Request(URL + path, data=body, method='POST', headers=headers or {})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode(), time.time() - t
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), time.time() - t


def get(path):
    try:
        with urllib.request.urlopen(URL + path, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return None, repr(e)


def wait_health(limit=120):
    t = time.time()
    while time.time() - t < limit:
        s, _ = get('/health')
        if s == 200:
            return time.time() - t
        time.sleep(0.5)
    return None


def unit_fixes():
    import dictate_srv as d
    cases = [
        ('post it in sap my go now', 'post it in sap MIGO now'),
        ('check migo and miro', 'check MIGO and MIRO'),
        ('the I doc failed', 'the IDoc failed'),
        ('two idocs failed', 'two IDocs failed'),
        ('on s for hana', 'on S/4HANA'),
        ('on S4 HANA today', 'on S/4HANA today'),
        ('in the S-4HANA system', 'in the S/4HANA system'),
        ('in the S/4HANA system', 'in the S/4HANA system'),
        ('on S four HANA', 'on S/4HANA'),
        ('this is for Hana the dog', 'this is for Hana the dog'),
        ('he runs as four hana tasks', 'he runs as four hana tasks'),
        ('open the fiori app', 'open the Fiori app'),
        ('use cloud code today', 'use Claude code today'),
        ('open code review', 'OpenCode review'),   # known trade-off, documented
        # false-positive guards: these must stay unchanged
        ('it is my go to place', 'it is my go to place'),
        ('cloud usage went up', 'cloud usage went up'),
        ('the opus on the radio', 'the opus on the radio'),
        ('I doctor the notes', 'I doctor the notes'),
        ('let me go home', 'let me go home'),
        ('what is hana', 'what is hana'),
        ('He said hello to the EPIC team', 'He said hello to the EPIC team'),
    ]
    bad = [(a, d.fix(a), b) for a, b in cases if d.fix(a) != b]
    check('fix(): %d rule cases' % len(cases), not bad, bad)
    # chunk splitter
    import numpy as np
    w = np.random.RandomState(0).randn(16000 * 70).astype('float32') * 0.1
    w[16000 * 24: 16000 * 24 + 1600] = 0.0   # a quiet gap at 24 s
    cuts = d.split_points(w)
    sizes = np.diff([0] + cuts + [len(w)]) / 16000
    check('split_points: every piece <= 28 s', sizes.max() <= 28.01, sizes.round(1).tolist())
    check('split_points: cut lands in the quiet gap', abs(cuts[0] / 16000 - 24.05) < 0.2, cuts[0] / 16000)
    check('split_points: short clip not cut', d.split_points(np.zeros(16000 * 10, dtype='float32')) == [])
    # vocabulary header parsing
    from urllib.parse import quote
    enc = lambda *t: ','.join(quote(x, safe='') for x in t)
    check('parse_vocabulary: plain terms', d.parse_vocabulary(enc('Novonesis', 'Kushi')) == ['Novonesis', 'Kushi'])
    check('parse_vocabulary: accents and slashes survive', d.parse_vocabulary(enc('Zoë', 'S/4HANA')) == ['Zoë', 'S/4HANA'])
    check('parse_vocabulary: dedupes any case, drops empty', d.parse_vocabulary('a,A,,%20,b') == ['a', 'b'])
    check('parse_vocabulary: bad percent escapes are skipped, not fatal', d.parse_vocabulary('%ZZ,%E0%A4%A,ok') == ['ok'])
    check('parse_vocabulary: control characters and long terms dropped', d.parse_vocabulary('a%0Ab,' + 'x' * 41 + ',fine') == ['fine'])
    check('parse_vocabulary: capped at %d terms' % d.MAX_VOCAB, len(d.parse_vocabulary(','.join('t%d' % i for i in range(80)))) == d.MAX_VOCAB)
    check('parse_vocabulary: None and empty header', d.parse_vocabulary(None) == [] and d.parse_vocabulary('') == [])


def start_server(idle):
    env = dict(os.environ)
    for k in ('PYTHONPATH', 'PYTHONHOME', 'VIRTUAL_ENV'):
        env.pop(k, None)
    return subprocess.Popen([sys.executable, str(SRV), 'serve', '--idle', str(idle)], env=env,
                            stdout=open(ROOT / 'server' / 'test_server.log', 'a'), stderr=subprocess.STDOUT)


def main():
    unit_fixes()
    if '--skip-model' in sys.argv:
        print(json.dumps({'passed': sum(r['ok'] for r in results), 'total': len(results)})); return
    refs = json.load(open(DATA / 'refs.json'))
    if get('/health')[0] == 200:
        print('port', PORT, 'already serving; stop it first'); sys.exit(2)
    p = start_server(idle=900)
    try:
        cold = wait_health(150)
        check('server loads and /health = ok', cold is not None, f'{cold:.1f}s' if cold else 'timeout')
        if cold is None:
            return
        ok_body = (DATA / 'plain1.wav').read_bytes()
        post('/transcribe', ok_body)   # warm-up, not scored

        # accuracy on 16 kHz mono clips
        times = {}
        for name in ('plain1', 'plain2', 'sap1', 'sap2', 'sap3', 'notsap1', 'notsap2'):
            s, text, dt = post('/transcribe', (DATA / f'{name}.wav').read_bytes())
            w = wer(refs[name], text)
            times[name] = dt
            check(f'transcribe {name}: HTTP 200 and WER <= 0.25', s == 200 and w <= 0.25, f'{s} wer={w:.2f} {dt:.2f}s "{text}"')
        # SAP terms in exact spelling
        terms = {'sap1': ['MIGO', 'MIRO'], 'sap2': ['IDoc', 'S/4HANA'], 'sap3': ['Fiori', 'OData', 'BTP']}
        for name, ts in terms.items():
            _, text, _ = post('/transcribe', (DATA / f'{name}.wav').read_bytes())
            miss = [t for t in ts if t not in text]
            check(f'exact SAP spelling {name}', not miss, f'missing {miss} in "{text}"')
        # false-positive guards through the live server
        _, t1, _ = post('/transcribe', (DATA / 'notsap1.wav').read_bytes())
        check('"my go to place" not rewritten to MIGO', 'MIGO' not in t1, t1)
        _, t2, _ = post('/transcribe', (DATA / 'notsap2.wav').read_bytes())
        check('"cloud usage" not rewritten to Claude', 'Claude' not in t2, t2)

        # format variants must give the same words as the 16 kHz clip
        _, base_text, _ = post('/transcribe', ok_body)
        for name in ('plain1_44k_stereo', 'plain1_8k', 'plain1_48k_f32'):
            s, text, dt = post('/transcribe', (DATA / f'{name}.wav').read_bytes())
            w = wer(refs['plain1'], text)
            check(f'format {name}: accepted, WER <= 0.25', s == 200 and w <= 0.25, f'{s} wer={w:.2f} "{text}"')

        # edge cases
        s, text, _ = post('/transcribe', (DATA / 'silence_2s.wav').read_bytes())
        check('silence -> 200 empty text', s == 200 and text == '', f'{s} "{text}"')
        s, text, _ = post('/transcribe', (DATA / 'short_0p12s.wav').read_bytes())
        check('0.12 s clip -> 200 empty text', s == 200 and text == '', f'{s} "{text}"')
        s, text, _ = post('/transcribe', (DATA / 'not_audio.wav').read_bytes())
        check('not audio -> 400', s == 400, f'{s} {text[:80]}')
        s, text, _ = post('/transcribe', b'')
        check('empty body -> 400', s == 400, f'{s} {text[:80]}')
        s, text, _ = post('/other', ok_body)
        check('wrong path -> 404', s == 404, s)
        s, _ = get('/nope')
        check('GET unknown -> 404', s == 404, s)

        # long clip: nothing lost beyond Whisper's 30 s window
        la_ref = refs['long_a'] * 5
        s, text, dt = post('/transcribe', (DATA / 'long_70s.wav').read_bytes(), timeout=300)
        w = wer(la_ref, text)
        check('79 s clip: WER <= 0.20 (no tail lost)', s == 200 and w <= 0.20, f'wer={w:.3f} words={len(norm(text))}/{len(norm(la_ref))} {dt:.1f}s')
        check('79 s clip: last sentence present', 'invoice verification backlog' in text.lower().replace('-', ' ')[-400:], text[-120:])

        # concurrency: 4 parallel requests all succeed and are correct
        out = [None] * 4
        def worker(i):
            out[i] = post('/transcribe', (DATA / 'sap1.wav').read_bytes())
        th = [threading.Thread(target=worker, args=(i,)) for i in range(4)]
        t0 = time.time(); [x.start() for x in th]; [x.join() for x in th]
        good = all(o and o[0] == 200 and wer(refs['sap1'], o[1]) <= 0.25 for o in out)
        check('4 parallel requests all correct', good, f'{time.time() - t0:.1f}s total')

        # vocabulary header: accepted, harmless when odd, and it must not slow or break normal clips
        from urllib.parse import quote
        h = lambda *t: {'X-Vocabulary': ','.join(quote(x, safe='') for x in t)}
        base_clip = (DATA / 'plain2.wav').read_bytes()
        s, text, _ = post('/transcribe', base_clip, headers=h('Novonesis', 'Kushi', 'Zoë'))
        check('vocabulary header: normal clip unchanged', s == 200 and wer(refs['plain2'], text) <= 0.25, f'{s} "{text}"')
        s, text, _ = post('/transcribe', base_clip, headers=h(*[('LongTermNumber%02d' % i) + 'x' * 20 for i in range(30)]))
        check('vocabulary header: 30 long terms (prompt over the limit) still works', s == 200 and wer(refs['plain2'], text) <= 0.25, f'{s} "{text}"')
        s, text, _ = post('/transcribe', base_clip, headers={'X-Vocabulary': '%ZZ,%E0%A4%A,,,%00'})
        check('vocabulary header: garbage is ignored, not an error', s == 200 and wer(refs['plain2'], text) <= 0.25, f'{s} "{text}"')
        _, no_v, _ = post('/transcribe', (DATA / 'vocab1.wav').read_bytes())
        _, with_v, _ = post('/transcribe', (DATA / 'vocab1.wav').read_bytes(), headers=h('Zorblax', 'Quenvarith'))
        hits = lambda t: sum(1 for w in ('Zorblax', 'Quenvarith') if w.lower() in t.lower())
        check('vocabulary header: invented names are spelled right more often with the hint', hits(with_v) > hits(no_v) or hits(with_v) == 2,
              f'without: "{no_v}" | with: "{with_v}"')

        # speed
        warm = [times[n] for n in times]
        check('warm latency < 3 s for clips <= 4 s', max(warm) < 3.0, f'max {max(warm):.2f}s median {sorted(warm)[len(warm)//2]:.2f}s')
    finally:
        p.send_signal(signal.SIGTERM)
        try:
            rc = p.wait(30)
            check('SIGTERM -> clean exit', rc == 0, f'rc={rc}')
        except subprocess.TimeoutExpired:
            p.kill(); check('SIGTERM -> clean exit', False, 'had to kill')

    # idle shutdown (own short server; /health must not reset the timer)
    p2 = start_server(idle=8)
    try:
        c = wait_health(150)
        check('idle server loads', c is not None)
        t0 = time.time()
        while time.time() - t0 < 5:
            get('/health'); time.sleep(0.5)
        exited = None
        for _ in range(40):
            if p2.poll() is not None:
                exited = time.time() - t0; break
            time.sleep(0.5)
        check('idle shutdown within ~8-14 s of last call, /health did not reset it', exited is not None and 7 <= exited <= 16, f'{exited}')
        check('idle exit code 0', p2.poll() == 0, p2.poll())
        check('port freed after idle exit', get('/health')[0] is None)
    finally:
        if p2.poll() is None:
            p2.kill()

    # touch=1 keeps the server alive (the app sends it when a key goes down)
    p3 = start_server(idle=8)
    try:
        c = wait_health(150)
        t0 = time.time()
        while time.time() - t0 < 14:
            s, _ = get('/health?touch=1')
            time.sleep(1)
        check('/health?touch=1 resets the idle timer (alive after 14 s with idle=8)', p3.poll() is None and s == 200, f'poll={p3.poll()}')
    finally:
        if p3.poll() is None:
            p3.send_signal(signal.SIGTERM); p3.wait(30)

    # two racing `start` commands: exactly one server, pid file names a live server of ours
    env = {k: v for k, v in os.environ.items() if k not in ('PYTHONPATH', 'PYTHONHOME', 'VIRTUAL_ENV')}
    starts = [subprocess.Popen([sys.executable, str(SRV), 'start', '--idle', '60'], env=env, stdout=subprocess.PIPE, text=True) for _ in range(2)]
    outs = [s.communicate()[0].strip() for s in starts]
    time.sleep(1)
    pid = int(open(HERE / 'dictate_srv.pid').read())
    alive = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
    check('racing starts: one "started", one "already running"', sorted(o.split()[0] for o in outs) == ['already', 'started'], outs)
    check('racing starts: pid file names the live server', 'dictate_srv.py' in alive, alive[:60])
    subprocess.run([sys.executable, str(SRV), 'stop'], capture_output=True)
    time.sleep(2)
    check('racing starts: stop leaves nothing running', subprocess.run([sys.executable, str(SRV), 'status'], capture_output=True, text=True).stdout.strip() == 'stopped')

    # stop never kills a pid that is not ours
    victim = subprocess.Popen(['sleep', '30'])
    pidfile = HERE / 'dictate_srv.pid'
    try:
        pidfile.write_text(str(victim.pid))
        out = subprocess.run([sys.executable, str(SRV), 'stop'], capture_output=True, text=True).stdout
        check('stop refuses a foreign pid', victim.poll() is None and 'not ours' in out, out.strip())
    finally:
        victim.kill(); victim.wait()
        if pidfile.exists():
            pidfile.unlink()

    print(json.dumps({'passed': sum(r['ok'] for r in results), 'total': len(results)}))
    json.dump(results, open(ROOT / 'tests-data' / 'server_results.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
