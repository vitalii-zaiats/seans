#!/usr/bin/env python3
"""
check.py — контроль якості згенерованих файлів.

Головне, що тут перевіряється — стик петлі, і саме на декодованому OGG,
а не на масиві в пам'яті: Vorbis лосі, і артефакт міг з'явитись уже
на кодуванні.
"""
import json, os, sys
import numpy as np
import soundfile as sf
from scipy import signal

out = sys.argv[1] if len(sys.argv) > 1 else "out"
man = json.load(open(os.path.join(out, "manifest.json")))

def db(v): return 20*np.log10(v) if v > 0 else -120.0

print(f"{'звук':16s} {'клип':>5s} {'DC':>7s} {'моно':>7s} {'низ':>5s} {'сер':>5s} {'верх':>5s} "
      f"{'ТВ':>6s} {'стик':>16s}")
print("─"*88)
bad = []
for s in man["sounds"]:
    x, sr = sf.read(os.path.join(out, s["file"]), always_2d=True)
    m = x.mean(axis=1)
    peak = np.max(np.abs(x))
    dc = np.max(np.abs(x.mean(axis=0)))
    # моно-сумісність: скільки втрачається при згортанні в моно (ТВ-динамік)
    mono_loss = db(np.sqrt(np.mean(m**2))) - db(np.sqrt(np.mean(x**2)))
    # спектральний баланс
    S = np.abs(np.fft.rfft(m * np.hanning(len(m))))**2
    f = np.fft.rfftfreq(len(m), 1/sr)
    tot = S.sum() + 1e-30
    lo, mid, hi = (S[f<120].sum()/tot, S[(f>=120)&(f<2000)].sum()/tot, S[f>=2000].sum()/tot)

    # що доживе до вбудованого динаміка ТВ: він нижче ~150 Гц не грає нічого
    sos = signal.butter(4, 150/(sr/2), "high", output="sos")
    tv = db(np.sqrt(np.mean(signal.sosfilt(sos, m)**2))) - db(np.sqrt(np.mean(m**2)))

    seam = ""
    if s["loop"]:
        # розрив на стику проти типової крутизни сигналу всередині петлі
        step = np.max(np.abs(x[0] - x[-1]))
        typical = np.percentile(np.abs(np.diff(x, axis=0)), 99.9)
        ratio = step / (typical + 1e-12)
        seam = f"×{ratio:5.2f} {'OK' if ratio < 3 else 'КЛАЦАЄ'}"
        if ratio >= 3: bad.append(s["name"] + ": стик")
    if peak >= 0.999: bad.append(s["name"] + ": клип")
    if abs(dc) > 0.01: bad.append(s["name"] + ": DC")
    if mono_loss < -4: bad.append(s["name"] + ": фаза в моно")

    if s["loop"] and tv < -12: bad.append(s["name"] + ": зникне на ТВ-динаміку")
    print(f"{s['name']:16s} {peak:5.3f} {dc:7.4f} {mono_loss:6.1f}d "
          f"{lo*100:4.0f}% {mid*100:4.0f}% {hi*100:4.0f}% {tv:5.1f}d {seam:>16s}")

print()
print("ПРОБЛЕМИ: " + ("; ".join(bad) if bad else "немає"))
