"""Shared helpers for the Dictate speech servers: SAP word fixes and audio preparation."""
import io, re

MIN_SECONDS = 0.3
SILENCE_RMS = 0.002

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
