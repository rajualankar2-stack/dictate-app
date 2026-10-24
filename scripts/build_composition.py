#!/usr/bin/env python3
"""Build the Dictate brag composition (v2, generic scenario).

Scene plan (30 s, 1920x1080):
  S1  0-4   the wrong word      generic mishearing, struck through, corrected
  S2  4-9   hold right Option   correct MacBook keyboard, real menu-bar states
  S3  9-14  the engine          model, on-device, private
  S4  14-19 the numbers         measured stats
  S5  19-25 your words, rules   the real Settings window + live demo
  S6  25-28 it lands            the real Gmail compose window
  S7  28-30 Dictate             logo

Run:  python3 build_composition.py <outdir>
"""
import json
import os
import re
import sys

OUT = sys.argv[1]
KB = open(os.path.join(OUT, 'composition/assets/img/keyboard.svg')).read()

# ---------------------------------------------------------------- the text
# S1: a real, generic mishearing this model actually makes.
S1_FULL = "Open "
S1_WRONG = "local host"   # what the model wrote
S1_RIGHT = "localhost"   # what it should be

# ---------------------------------------------------------------- audio bed
AUDIO = json.load(open(os.path.join(OUT, 'composition/assets/audio-data.json')))
AUDIO_JSON = json.dumps(AUDIO, separators=(',', ':'))

# ---------------------------------------------------------------- helpers
def sfx(aid, src, start, dur, vol, track=101):
    return ('    <audio id="%s" class="clip" src="assets/sfx/%s" data-start="%s" '
            'data-duration="%s" data-track-index="%d" data-volume="%s"></audio>\n'
            % (aid, src, start, dur, track, vol))

# ---------------------------------------------------------------- css
CSS = """
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body {
        width: 1920px; height: 1080px; overflow: hidden;
        background: #0B1020;
        font-family: Inter, "Helvetica Neue", Arial, sans-serif;
        -webkit-font-smoothing: antialiased;
      }
      #root { position: relative; width: 100%; height: 100%; overflow: hidden; background: #0B1020; }
      .clip { position: absolute; inset: 0; }
      .scene { display: flex; align-items: center; justify-content: center; z-index: 50; }

      .kicker { font-size: 22px; font-weight: 600; letter-spacing: 0.22em; text-transform: uppercase; color: #0D9E9E; }
      .h2 { font-size: 66px; font-weight: 700; letter-spacing: -0.03em; color: #F2F5FA; line-height: 1.1; }
      .sub { font-size: 30px; font-weight: 400; color: #8C93A6; line-height: 1.45; }
      .accent { color: #0D9E9E; }
      .blue { color: #2161DB; }
      .teal { color: #7FE3E3; }

      /* ---------- S1: the wrong word ---------- */
      #s1-wrap { flex-direction: column; gap: 54px; }
      #s1-field {
        width: 1240px; height: 172px; border-radius: 18px;
        background: #141A2E; border: 1px solid #242C46;
        display: flex; align-items: center; padding: 0 46px;
        font-size: 48px; font-weight: 500; color: #F2F5FA; letter-spacing: -0.01em;
      }
      #s1-caret { width: 3px; height: 54px; background: #0D9E9E; margin-left: 7px; }
      #s1-text { display: flex; align-items: center; }
      #s1-prefix { white-space: pre; }
      #s1-wrong {
        position: relative; color: #7C8398; opacity: 0; white-space: pre;
        display: inline-block; vertical-align: baseline; overflow: hidden;
      }
      #s1-right { color: #F2F5FA; opacity: 0; white-space: pre; }
      #s1-strike {
        position: absolute; left: -4px; right: -4px; top: 50%; height: 4px;
        background: #E5484D; border-radius: 2px; transform-origin: left center;
      }
      #s1-caption { width: 1240px; }

      /* ---------- S2: the key ---------- */
      #s2-wrap { flex-direction: column; gap: 40px; align-items: center; }
      #s2-stage { display: flex; align-items: center; gap: 56px; }
      #s2-kbd { position: relative; width: 1000px; height: 266px; flex: 0 0 1000px; }
      #s2-kbd-inner { position: absolute; left: 0; top: 0; width: 1620px; height: 430px; transform: scale(0.6173); transform-origin: top left; }
      #s2-kbd svg { width: 100%; height: 100%; }
      #s2-panel { width: 560px; flex: 0 0 560px; }
      #s2-timer { width: 280px; height: 8px; border-radius: 4px; background: #1E2640; overflow: hidden; margin-top: 20px; }
      #s2-timer-fill { width: 0%; height: 100%; background: #0D9E9E; border-radius: 4px; }
      #s2-menubar {
        display: flex; align-items: center; gap: 18px; padding: 16px 28px;
        background: #141A2E; border: 1px solid #242C46; border-radius: 16px; margin-top: 34px;
      }
      #s2-menubar .mm {
        width: 46px; height: 46px; border-radius: 10px; display: flex; align-items: center; justify-content: center;
        background: #1E2640;
      }
      #s2-menubar .mm img { width: 30px; height: 30px; }
      #s2-menubar .mm.on { background: #2A1A24; box-shadow: 0 0 0 1px #E5484D inset; }
      #s2-wave { display: flex; align-items: center; gap: 5px; height: 46px; }
      #s2-wave span { display: block; width: 5px; height: 10px; border-radius: 3px; background: #0D9E9E; }

      /* ---------- S3: the engine ---------- */
      #s3-wrap { flex-direction: column; align-items: flex-start; gap: 48px; padding-left: 190px; width: 100%; }
      #s3-rows { display: flex; flex-direction: column; gap: 42px; }
      .s3-row { display: flex; align-items: center; gap: 36px; }
      .s3-row svg { width: 78px; height: 78px; flex: 0 0 78px; }
      .s3-text { font-size: 62px; font-weight: 700; letter-spacing: -0.03em; color: #F2F5FA; }
      #s3-kicker { position: absolute; left: 190px; top: 100px; }

      /* ---------- S4: numbers ---------- */
      #s4-wrap { flex-direction: column; gap: 70px; width: 100%; }
      #s4-stats { display: flex; gap: 38px; justify-content: center; }
      .s4-stat {
        width: 400px; height: 252px; border-radius: 22px; background: #141A2E; border: 1px solid #242C46;
        display: flex; flex-direction: column; justify-content: center; padding: 0 38px; gap: 16px;
      }
      .s4-num { font-size: 76px; font-weight: 800; letter-spacing: -0.04em; color: #F2F5FA; line-height: 1; }
      .s4-lab { font-size: 23px; font-weight: 500; color: #8C93A6; line-height: 1.35; }
      #s4-note { font-size: 27px; color: #8C93A6; text-align: center; }

      /* ---------- S5: settings ---------- */
      #s5-wrap { flex-direction: column; gap: 40px; width: 100%; }
      #s5-row { display: flex; align-items: center; gap: 60px; justify-content: center; }
      #s5-shot {
        width: 700px; height: 800px; border-radius: 18px; overflow: hidden;
        border: 1px solid #242C46; box-shadow: 0 40px 100px rgba(0,0,0,0.55);
      }
      #s5-shot img { width: 100%; height: 100%; object-fit: cover; object-position: top center; }
      #s5-demo { width: 640px; display: flex; flex-direction: column; gap: 36px; }
      .s5-box { background: #141A2E; border: 1px solid #242C46; border-radius: 18px; padding: 30px 34px; }
      .s5-lab { font-size: 20px; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; color: #8C93A6; margin-bottom: 20px; }
      .s5-input {
        display: flex; align-items: center; gap: 16px; height: 60px; border-radius: 10px;
        background: #0E1426; border: 1px solid #2C3552; padding: 0 20px; font-size: 28px; color: #F2F5FA;
      }
      .s5-chip {
        display: inline-flex; align-items: center; height: 46px; padding: 0 18px; border-radius: 23px;
        background: rgba(13,158,158,0.16); border: 1px solid #0D9E9E; color: #7FE3E3; font-size: 24px; font-weight: 600;
      }
      .s5-rule { display: flex; align-items: center; gap: 16px; font-size: 30px; }
      .s5-arrow { color: #0D9E9E; }
      .s5-out { color: #7FE3E3; font-weight: 600; }
      .s5-old { color: #7C8398; text-decoration: line-through; text-decoration-color: #E5484D; }

      /* ---------- S6: the paste ---------- */
      #s6-wrap { flex-direction: column; gap: 30px; align-items: center; }
      #s6-app { font-size: 21px; font-weight: 600; letter-spacing: 0.2em; text-transform: uppercase; color: #8C93A6; }
      #s6-shot {
        width: 1420px; border-radius: 20px; overflow: hidden;
        border: 1px solid #242C46; box-shadow: 0 40px 100px rgba(0,0,0,0.55); background: #0E1426;
      }
      #s6-shot img { width: 100%; display: block; }
      #s6-note { font-size: 30px; color: #8C93A6; }
      #s6-note b { color: #F2F5FA; font-weight: 600; }

      /* ---------- S7: the logo ---------- */
      #s7-wrap { flex-direction: column; gap: 46px; }
      #s7-icon { width: 300px; height: 300px; position: relative; }
      #s7-icon img { width: 100%; height: 100%; border-radius: 68px; }
      #s7-glow {
        position: absolute; inset: -70px; border-radius: 140px; z-index: -1;
        background: radial-gradient(circle, rgba(13,158,158,0.42) 0%, rgba(13,158,158,0) 68%);
      }
      #s7-name { font-size: 112px; font-weight: 800; letter-spacing: -0.045em; color: #F2F5FA; }
      #s7-tag { font-size: 34px; font-weight: 500; color: #8C93A6; letter-spacing: 0.01em; }

      .vignette {
        position: absolute; inset: 0; z-index: 40; pointer-events: none;
        background: radial-gradient(ellipse at center, rgba(11,16,32,0) 45%, rgba(11,16,32,0.72) 100%);
      }
      .grain {
        position: absolute; inset: 0; z-index: 41; pointer-events: none; opacity: 0.05;
        background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='3'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)'/%3E%3C/svg%3E");
      }
"""

# ---------------------------------------------------------------- markup
def build_markup():
    m = []
    m.append('      <!-- ============ SCENE 1 — the wrong word (0 - 4) ============ -->')
    m.append('      <section id="s1" class="clip scene" data-start="0" data-duration="4" data-track-index="0">')
    m.append('        <div id="s1-wrap">')
    m.append('          <div id="s1-field">')
    m.append('            <span id="s1-text">')
    m.append('              <span id="s1-prefix"></span><span id="s1-wrong"><span id="s1-wrong-text"></span><span id="s1-strike"></span></span><span id="s1-right"></span>')
    m.append('            </span><span id="s1-caret"></span>')
    m.append('          </div>')
    m.append('          <div id="s1-caption">')
    m.append('            <div class="h2">Dictation that knows <span class="accent">your</span> words</div>')
    m.append('            <div class="sub" style="margin-top:16px;">Your own model, on your own machine.</div>')
    m.append('          </div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 2 — hold right Option (4 - 9) ============ -->')
    m.append('      <section id="s2" class="clip scene" data-start="4" data-duration="5" data-track-index="1">')
    m.append('        <div id="s2-wrap">')
    m.append('          <div id="s2-stage">')
    m.append('            <div id="s2-kbd">')
    m.append('              <div id="s2-kbd-inner">')
    m.append('              ' + KB.replace('\n', '\n              '))
    m.append('              </div>')
    m.append('            </div>')
    m.append('            <div id="s2-panel">')
    m.append('              <div class="h2">Hold the right Option key</div>')
    m.append('              <div class="sub" style="margin-top:14px;">0.30 s, then speak.<br />A quick tap does nothing.</div>')
    m.append('              <div id="s2-timer"><div id="s2-timer-fill"></div></div>')
    m.append('              <div id="s2-menubar">')
    m.append('                <div class="mm" id="s2-mm-idle"><img src="assets/img/icon_idle.png" alt="" /></div>')
    m.append('                <div class="mm on" id="s2-mm-rec"><img src="assets/img/icon_recording.png" alt="" /></div>')
    m.append('                <div id="s2-wave"></div>')
    m.append('              </div>')
    m.append('            </div>')
    m.append('          </div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 3 — the engine (9 - 14) ============ -->')
    m.append('      <section id="s3" class="clip scene" data-start="9" data-duration="5" data-track-index="2">')
    m.append('        <div id="s3-kicker"><div class="kicker">The engine</div></div>')
    m.append('        <div id="s3-wrap">')
    m.append('          <div id="s3-rows">')
    m.append('            <div class="s3-row" id="s3-r1">')
    m.append('              <svg viewBox="0 0 76 76" fill="none" stroke="#0D9E9E" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">')
    m.append('                <rect x="14" y="18" width="48" height="40" rx="8" /><rect x="26" y="28" width="24" height="20" rx="4" />')
    m.append('                <path d="M24 44h28M24 36h28M32 52v6M44 52v6M24 58h28" />')
    m.append('              </svg>')
    m.append('              <div class="s3-text">Whisper-small <span class="accent">+ my own LoRA adapter</span></div>')
    m.append('            </div>')
    m.append('            <div class="s3-row" id="s3-r2">')
    m.append('              <svg viewBox="0 0 76 76" fill="none" stroke="#2161DB" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">')
    m.append('                <rect x="12" y="16" width="52" height="34" rx="6" /><path d="M26 58h24M38 50v8" />')
    m.append('              </svg>')
    m.append('              <div class="s3-text">Runs on <span class="blue">this Mac</span></div>')
    m.append('            </div>')
    m.append('            <div class="s3-row" id="s3-r3">')
    m.append('              <svg viewBox="0 0 76 76" fill="none" stroke="#0D9E9E" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">')
    m.append('                <path d="M38 12l22 8v18c0 14-9 23-22 27-13-4-22-13-22-27V20l22-8z" /><path d="M29 38l7 7 13-14" />')
    m.append('              </svg>')
    m.append('              <div class="s3-text">Audio <span class="accent">never</span> leaves the machine</div>')
    m.append('            </div>')
    m.append('          </div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 4 — the numbers (14 - 19) ============ -->')
    m.append('      <section id="s4" class="clip scene" data-start="14" data-duration="5" data-track-index="3">')
    m.append('        <div id="s4-wrap">')
    m.append('          <div id="s4-stats">')
    m.append('            <div class="s4-stat" id="s4-a">')
    m.append('              <div class="s4-num"><span id="s4-a-num">0.00</span><span class="accent">%</span></div>')
    m.append('              <div class="s4-lab">word error rate<br />30 clips of my own voice</div>')
    m.append('            </div>')
    m.append('            <div class="s4-stat" id="s4-b">')
    m.append('              <div class="s4-num"><span id="s4-b-num">0.0</span><span class="accent"> s</span></div>')
    m.append('              <div class="s4-lab">per clip, warm<br />p95 1.43 s</div>')
    m.append('            </div>')
    m.append('            <div class="s4-stat" id="s4-c">')
    m.append('              <div class="s4-num"><span id="s4-c-num">0</span><span class="accent"> s</span></div>')
    m.append('              <div class="s4-lab">model load<br />starts on first key press</div>')
    m.append('            </div>')
    m.append('            <div class="s4-stat" id="s4-d">')
    m.append('              <div class="s4-num"><span id="s4-d-num">0.00</span><span class="accent"> GB</span></div>')
    m.append('              <div class="s4-lab">memory while running<br />then it stops itself</div>')
    m.append('            </div>')
    m.append('          </div>')
    m.append('          <div id="s4-note" class="sub">It shuts itself down after 10 idle minutes, and frees the memory.</div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 5 — your words, your rules (19 - 25) ============ -->')
    m.append('      <section id="s5" class="clip scene" data-start="19" data-duration="6" data-track-index="4">')
    m.append('        <div id="s5-wrap">')
    m.append('          <div id="s5-row">')
    m.append('            <div id="s5-shot"><img src="assets/img/settings_words.png" alt="Dictate Settings window, Words tab" /></div>')
    m.append('            <div id="s5-demo">')
    m.append('              <div class="s5-box">')
    m.append('                <div class="s5-lab">Vocabulary</div>')
    m.append('                <div class="s5-input"><span id="s5-typed">Kubernetes</span><span id="s5-caret" style="width:2px;height:32px;background:#0D9E9E;display:inline-block"></span></div>')
    m.append('                <div style="margin-top:22px;"><span class="s5-chip" id="s5-chip">Kubernetes</span></div>')
    m.append('              </div>')
    m.append('              <div class="s5-box">')
    m.append('                <div class="s5-lab">Replacements</div>')
    m.append('                <div class="s5-rule">')
    m.append('                  <span class="s5-old" id="s5-old">wipe coding</span>')
    m.append('                  <span class="s5-arrow">&rarr;</span>')
    m.append('                  <span class="s5-out" id="s5-new">vibe coding</span>')
    m.append('                </div>')
    m.append('                <div class="sub" style="margin-top:18px; font-size:23px;">Applied to the finished text, whole words only.</div>')
    m.append('              </div>')
    m.append('            </div>')
    m.append('          </div>')
    m.append('          <div class="sub" style="text-align:center;">Add the names you say. Fix the words you mean.</div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 6 — it lands in Gmail (25 - 28) ============ -->')
    m.append('      <section id="s6" class="clip scene" data-start="25" data-duration="3" data-track-index="5">')
    m.append('        <div id="s6-wrap">')
    m.append('          <div id="s6-app">Straight into the app you were already in</div>')
    m.append('          <div id="s6-shot"><img src="assets/img/paste_gmail.png" alt="Dictated text pasted into a Gmail draft" /></div>')
    m.append('          <div id="s6-note">A real <b>Gmail</b> draft. Your clipboard comes back.</div>')
    m.append('        </div>')
    m.append('      </section>')

    m.append('      <!-- ============ SCENE 7 — the logo (28 - 30) ============ -->')
    m.append('      <section id="s7" class="clip scene" data-start="28" data-duration="2" data-track-index="6">')
    m.append('        <div id="s7-wrap">')
    m.append('          <div id="s7-icon">')
    m.append('            <div id="s7-glow"></div>')
    m.append('            <img src="assets/img/icon.png" alt="Dictate app icon" />')
    m.append('          </div>')
    m.append('          <div id="s7-name">Dictate</div>')
    m.append('          <div id="s7-tag">Your voice. Your words. Your Mac.</div>')
    m.append('        </div>')
    m.append('      </section>')
    return '\n'.join(m)


# ---------------------------------------------------------------- script
def build_script(wer):
    s = []
    a = s.append
    a('      const S1_FULL = %s;' % json.dumps(S1_FULL))
    a('      const S1_WRONG = %s;' % json.dumps(S1_WRONG))
    a('      const S1_RIGHT = %s;' % json.dumps(S1_RIGHT))
    a('      const WER_VALUE = %s;' % wer)
    a('      var AUDIO_DATA = %s;' % AUDIO_JSON)
    a('')
    a('      const tl = gsap.timeline({ paused: true });')
    a('')
    a('      // ============ SCENE 1 — the wrong word ============')
    a('      (function () {')
    a('        const prefixEl = document.getElementById("s1-prefix");')
    a('        const wrongText = document.getElementById("s1-wrong-text");')
    a('        const rightEl = document.getElementById("s1-right");')
    a('        const total = S1_FULL.length;')
    a('        for (let i = 0; i < total; i++) {')
    a('          tl.call((function (txt) { return function () { prefixEl.textContent = txt; }; })(S1_FULL.slice(0, i + 1)), [], 0.12 + i * 0.06);')
    a('        }')
    a('        const tWrong = 0.12 + total * 0.06;')
    a('        tl.call(function () { wrongText.textContent = S1_WRONG; }, [], tWrong);')
    a('        tl.set("#s1-wrong", { opacity: 1 }, tWrong);')
    a('        tl.fromTo("#s1-strike", { scaleX: 0 }, { scaleX: 1, duration: 0.35, ease: "power2.inOut" }, tWrong + 0.3);')
    a('        const tRight0 = 2.55;')
    a('        tl.to("#s1-wrong", { opacity: 0, width: 0, duration: 0.22, ease: "power2.in" }, tRight0 - 0.22);')
    a('        tl.set("#s1-right", { opacity: 1 }, tRight0);')
    a('        for (let i = 1; i <= S1_RIGHT.length; i++) {')
    a('          tl.call((function (txt) { return function () { rightEl.textContent = txt; }; })(S1_RIGHT.slice(0, i)), [], tRight0 + i * 0.085);')
    a('        }')
    a('        tl.set("#s1-right", { color: "#7FE3E3" }, 3.05);')
    a('        tl.fromTo("#s1-caret", { opacity: 1 }, { opacity: 0.25, duration: 0.5, repeat: 3, yoyo: true }, 0);')
    a('        tl.fromTo("#s1-field", { opacity: 0, y: 26 }, { opacity: 1, y: 0, duration: 0.5, ease: "power3.out" }, 0.05);')
    a('        tl.fromTo("#s1-caption", { opacity: 0, y: 18 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, 1.6);')
    a('      })();')
    a('')
    a('      // ============ SCENE 2 — hold right Option ============')
    a('      tl.fromTo("#s2-kbd", { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 0.6, ease: "power3.out" }, 4.05);')
    a('      tl.fromTo("#s2-panel", { opacity: 0, x: 30 }, { opacity: 1, x: 0, duration: 0.6, ease: "power3.out" }, 4.25);')
    a('      // the right Option key goes down (ids from the generated keyboard SVG)')
    a('      // The key label is a separate <text> drawn AFTER the fill rect, so the fill')
    a('      // never hides it. It is re-coloured to white so it stays readable.')
    a('      tl.fromTo("#kbd-opt-glow", { opacity: 0, scale: 0.9 }, { opacity: 0.55, scale: 1, duration: 0.25, ease: "back.out(2)" }, 4.95);')
    a('      tl.fromTo("#kbd-opt-ring", { opacity: 0, scale: 1.1 }, { opacity: 1, scale: 1, duration: 0.3, ease: "power2.out" }, 4.95);')
    a('      tl.to("#kbd-opt-right", { fill: "#0D9E9E", duration: 0.18 }, 4.95);')
    a('      tl.to("#kbd-opt-label", { fill: "#FFFFFF", duration: 0.18 }, 4.95);')
    a('      tl.to("#kbd-opt-glow", { opacity: 0, duration: 0.25 }, 6.2);')
    a('      tl.to("#kbd-opt-ring", { opacity: 0, duration: 0.25 }, 6.2);')
    a('      tl.to("#kbd-opt-right", { fill: "#26314F", duration: 0.25 }, 6.2);')
    a('      tl.to("#kbd-opt-label", { fill: "#C3C9D9", duration: 0.25 }, 6.2);')
    a('      // the hold timer fills for 0.30 s')
    a('      tl.fromTo("#s2-timer-fill", { width: "0%" }, { width: "100%", duration: 0.3, ease: "none" }, 4.95);')
    a('      // the menu bar swaps idle -> recording')
    a('      tl.to("#s2-mm-idle", { opacity: 0.3, duration: 0.2 }, 5.25);')
    a('      tl.to("#s2-mm-rec", { opacity: 1, duration: 0.2 }, 5.25);')
    a('      (function () {')
    a('        const wave = document.getElementById("s2-wave");')
    a('        for (let i = 0; i < 16; i++) { wave.appendChild(document.createElement("span")); }')
    a('        const bars = wave.querySelectorAll("span");')
    a('        const grid = [5.25, 5.5, 5.75, 6.0, 6.25, 6.5, 6.75, 7.0, 7.25, 7.5, 7.75, 8.0, 8.25, 8.5];')
    a('        // Deterministic heights from the audio RMS, never Math.random().')
    a('        bars.forEach(function (b, i) {')
    a('          const t = grid[i % grid.length];')
    a('          const f = AUDIO_DATA.frames[Math.min(AUDIO_DATA.frames.length - 1, Math.round(t * 30))];')
    a('          const h = 8 + (f ? f.bands[6] * 34 : 12);')
    a('          tl.fromTo(b, { height: 8 }, { height: h, duration: 0.16, ease: "power2.out" }, t);')
    a('          tl.to(b, { height: 8 + ((i * 7) % 14), duration: 0.22, ease: "power2.inOut" }, t + 0.18);')
    a('        });')
    a('      })();')
    a('')
    a('      // ============ SCENE 3 — the engine ============')
    a('      tl.fromTo("#s3-kicker", { opacity: 0, y: -12 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, 9.1);')
    a('      tl.fromTo("#s3-r1", { opacity: 0, x: -26 }, { opacity: 1, x: 0, duration: 0.55, ease: "power3.out" }, 9.5);')
    a('      tl.fromTo("#s3-r2", { opacity: 0, x: -26 }, { opacity: 1, x: 0, duration: 0.55, ease: "power3.out" }, 10.7);')
    a('      tl.fromTo("#s3-r3", { opacity: 0, x: -26 }, { opacity: 1, x: 0, duration: 0.55, ease: "power3.out" }, 11.9);')
    a('')
    a('      // ============ SCENE 4 — the numbers ============')
    a('      (function () {')
    a('        const cards = ["#s4-a", "#s4-b", "#s4-c", "#s4-d"];')
    a('        cards.forEach(function (sel, i) {')
    a('          tl.fromTo(sel, { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 0.5, ease: "power3.out" }, 14.1 + i * 0.22);')
    a('        });')
    a('        tl.fromTo("#s4-note", { opacity: 0 }, { opacity: 1, duration: 0.6 }, 15.6);')
    a('        // Counters. There is no built-in count-up element, so the number is written')
    a('        // on every frame of the tween via onUpdate. The final value is exact.')
    a('        const stats = [')
    a('          { el: "#s4-a-num", to: WER_VALUE, dp: 2 },')
    a('          { el: "#s4-b-num", to: 1.2, dp: 1 },')
    a('          { el: "#s4-c-num", to: 5, dp: 0 },')
    a('          { el: "#s4-d-num", to: 1.65, dp: 2 },')
    a('        ];')
    a('        stats.forEach(function (s, i) {')
    a('          const node = document.querySelector(s.el);')
    a('          const obj = { v: 0 };')
    a('          const t0 = 14.35 + i * 0.22;')
    a('          tl.to(obj, {')
    a('            v: s.to,')
    a('            duration: 0.7,')
    a('            ease: "power2.out",')
    a('            onUpdate: function () { node.textContent = obj.v.toFixed(s.dp); },')
    a('            onComplete: function () { node.textContent = s.to.toFixed(s.dp); }')
    a('          }, t0);')
    a('        });')
    a('      })();')
    a('')
    a('      // ============ SCENE 5 — your words, your rules ============')
    a('      tl.fromTo("#s5-shot", { opacity: 0, x: -26 }, { opacity: 1, x: 0, duration: 0.6, ease: "power3.out" }, 19.1);')
    a('      tl.fromTo("#s5-demo", { opacity: 0, x: 26 }, { opacity: 1, x: 0, duration: 0.6, ease: "power3.out" }, 19.3);')
    a('      // the vocabulary word types, then lands as a chip')
    a('      (function () {')
    a('        const typed = document.getElementById("s5-typed");')
    a('        const chip = document.getElementById("s5-chip");')
    a('        const word = "Kubernetes";')
    a('        chip.style.opacity = 0;')
    a('        for (let i = 1; i <= word.length; i++) {')
    a('          tl.call((function (txt) { return function () { typed.textContent = txt; }; })(word.slice(0, i)), [], 19.9 + i * 0.045);')
    a('        }')
    a('        tl.fromTo(chip, { opacity: 0, scale: 0.85 }, { opacity: 1, scale: 1, duration: 0.35, ease: "back.out(1.8)" }, 20.8);')
    a('      })();')
    a('      // the replacement rewrites the old phrase')
    a('      (function () {')
    a('        const oldEl = document.getElementById("s5-old");')
    a('        const newEl = document.getElementById("s5-new");')
    a('        // The swap is atomic: the old phrase and the new one change at the same')
    a('        // moment, so there is never a frame with an empty gap after the arrow.')
    a('        newEl.style.opacity = 0;')
    a('        tl.to(oldEl, { opacity: 0.3, duration: 0.25 }, 21.55);')
    a('        tl.fromTo(newEl, { opacity: 0, x: -12 }, { opacity: 1, x: 0, duration: 0.35, ease: "power2.out" }, 21.55);')
    a('      })();')
    a('')
    a('      // ============ SCENE 6 — it lands in Gmail ============')
    a('      tl.fromTo("#s6-app", { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, 25.05);')
    a('      tl.fromTo("#s6-shot", { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 0.6, ease: "power3.out" }, 25.2);')
    a('      tl.fromTo("#s6-note", { opacity: 0 }, { opacity: 1, duration: 0.5 }, 25.9);')
    a('')
    a('      // ============ SCENE 7 — the logo ============')
    a('      tl.fromTo("#s7-icon", { opacity: 0, scale: 0.86 }, { opacity: 1, scale: 1, duration: 0.7, ease: "power3.out" }, 28.05);')
    a('      tl.fromTo("#s7-name", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.6, ease: "power3.out" }, 28.2);')
    a('      tl.fromTo("#s7-tag", { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.6, ease: "power2.out" }, 28.45);')
    a('      tl.fromTo("#s7-glow", { opacity: 0, scale: 0.9 }, { opacity: 1, scale: 1, duration: 1.1, ease: "power2.inOut" }, 28.1);')
    a('')
    a('      // The framework controls clip visibility from data-start/data-duration, so the')
    a('      // scene boundaries must NOT be tweened here. Each scene fades its own content in.')
    a('')
    a('      // ---------- register the timeline so the runtime can play it ----------')
    a('      window.__timelines = window.__timelines || {};')
    a('      window.__timelines["main"] = tl;')
    return '\n'.join(s)


# ---------------------------------------------------------------- audio
def build_audio():
    a = []
    a.append('    <audio id="music-bed" src="assets/music/bed.mp3" data-start="0" data-duration="30" data-track-index="100" data-volume="0.22"')
    a.append('      data-fade-out-start="28.6" data-fade-out-duration="1.2"></audio>')
    # Per-character key ticks while S1 types. Each tick gets its own track so no two
    # ever overlap (HyperFrames flags overlapping clips on the same track).
    for i in range(5):
        a.append(sfx('sfx-type-%d' % (i + 1), 'key.wav', round(0.12 + i * 0.06, 3), 0.06, 0.16, 101 + i))
    a.append(sfx('sfx-wrong', 'tick.ogg', 0.46, 0.19, 0.5, 110))
    a.append(sfx('sfx-fix', 'switch.ogg', 2.55, 0.2, 0.45, 111))
    a.append(sfx('sfx-keypress', 'click.ogg', 4.95, 0.12, 0.5, 112))
    a.append(sfx('sfx-rec', 'switch.ogg', 5.25, 0.2, 0.35, 113))
    for i in range(4):
        a.append(sfx('sfx-stat-%d' % (i + 1), 'click.ogg', round(14.9 + i * 0.22, 3), 0.1, 0.35, 120 + i))
    a.append(sfx('sfx-chip', 'click.ogg', 20.8, 0.12, 0.4, 124))
    a.append(sfx('sfx-rewrite', 'switch.ogg', 21.9, 0.2, 0.35, 125))
    a.append(sfx('sfx-paste', 'thud.ogg', 25.25, 0.35, 0.55, 126))
    a.append(sfx('sfx-logo', 'thud.ogg', 28.1, 0.5, 0.5, 127))
    return '\n'.join(a)


def main():
    wer = os.environ.get('DICTATE_WER', '5.78')
    html = []
    html.append('<!doctype html>')
    html.append('<html lang="en">')
    html.append('  <head>')
    html.append('    <meta charset="UTF-8" />')
    html.append('    <meta name="viewport" content="width=1920, height=1080" />')
    html.append('    <title>Dictate — launch video</title>')
    html.append('    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>')
    html.append('    <style>')
    html.append(CSS)
    html.append('    </style>')
    html.append('  </head>')
    html.append('  <body>')
    html.append('    <div id="root" data-composition-id="main" data-start="0" data-duration="30" data-width="1920" data-height="1080">')
    html.append(build_markup())
    html.append('      <div class="vignette"></div>')
    html.append('      <div class="grain"></div>')
    html.append('    </div>')
    html.append('    <!-- ===== AUDIO ===== -->')
    html.append(build_audio())
    html.append('    <script>')
    html.append(build_script(wer))
    html.append('    </script>')
    html.append('  </body>')
    html.append('</html>')
    path = os.path.join(OUT, 'composition/index.html')
    with open(path, 'w') as f:
        f.write('\n'.join(html))
    print('wrote %s (%d bytes)' % (path, os.path.getsize(path)))


if __name__ == '__main__':
    main()
