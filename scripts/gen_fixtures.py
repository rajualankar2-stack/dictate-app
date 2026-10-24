#!/usr/bin/env python3
"""Generate test fixtures into tests-data/ with macOS `say` + ffmpeg. Safe to re-run."""
import json, subprocess, sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / 'tests-data'
OUT.mkdir(exist_ok=True)
FF = '/opt/homebrew/bin/ffmpeg'

# name -> (voice, text). Text is what the speech engine reads; `ref` is what we expect back.
SAYS = {
    'plain1': ('Rishi', 'Please send me the report by Friday afternoon.'),
    'plain2': ('Tara', 'The meeting starts at ten and we need the slides ready.'),
    'sap1': ('Rishi', 'Post the goods receipt in MIGO and then check the invoice in MIRO.'),
    'sap2': ('Tara', 'The IDoc failed in the S four HANA system, so we raised an incident.'),
    'sap3': ('Rishi', 'Open the Fiori app and check the OData service in BTP.'),
    'notsap1': ('Tara', 'It is my go to place for lunch.'),
    'notsap2': ('Rishi', 'Cloud usage went up last month.'),
    'vocab1': ('Tara', 'Please ask Zorblax about the Quenvarith report.'),
    'long_a': ('Rishi', 'First we reviewed the purchase order process and agreed that the approval steps are too slow. '
                         'Then we looked at the goods receipt posting and how the plant teams handle exceptions. '
                         'After that we talked about the invoice verification backlog and who owns each item. '),
}


def sh(*a):
    subprocess.run(a, check=True, capture_output=True)


def main():
    ref = {}
    for name, (voice, text) in SAYS.items():
        aiff = OUT / f'{name}.aiff'
        sh('say', '-v', voice, '-o', str(aiff), text)
        sh(FF, '-y', '-i', str(aiff), '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', str(OUT / f'{name}.wav'))
        aiff.unlink()
        ref[name] = text
    # format variants of plain1
    p = str(OUT / 'plain1.wav')
    sh(FF, '-y', '-i', p, '-ar', '44100', '-ac', '2', '-c:a', 'pcm_s16le', str(OUT / 'plain1_44k_stereo.wav'))
    sh(FF, '-y', '-i', p, '-ar', '8000', '-ac', '1', '-c:a', 'pcm_s16le', str(OUT / 'plain1_8k.wav'))
    sh(FF, '-y', '-i', p, '-ar', '48000', '-ac', '1', '-c:a', 'pcm_f32le', str(OUT / 'plain1_48k_f32.wav'))
    # silence, near-silence noise, very short clip
    sh(FF, '-y', '-f', 'lavfi', '-i', 'anullsrc=r=16000:cl=mono', '-t', '2', '-c:a', 'pcm_s16le', str(OUT / 'silence_2s.wav'))
    sh(FF, '-y', '-i', p, '-t', '0.12', '-c:a', 'pcm_s16le', str(OUT / 'short_0p12s.wav'))
    # long clip: long_a repeated to ~70 s with a short pause between repeats
    la = str(OUT / 'long_a.wav')
    lst = OUT / 'long_list.txt'
    lst.write_text(''.join(f"file '{la}'\n" for _ in range(5)))
    sh(FF, '-y', '-f', 'concat', '-safe', '0', '-i', str(lst), '-c:a', 'pcm_s16le', str(OUT / 'long_70s.wav'))
    lst.unlink()
    (OUT / 'not_audio.wav').write_bytes(b'this is not a wav file at all')
    (OUT / 'refs.json').write_text(json.dumps(ref, indent=1))
    for f in sorted(OUT.glob('*.wav')):
        d = subprocess.run(['/opt/homebrew/bin/ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(f)],
                           capture_output=True, text=True).stdout.strip()
        print(f.name, d)


if __name__ == '__main__':
    sys.exit(main())
