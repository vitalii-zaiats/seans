#!/usr/bin/env python3
"""
Генератор UI-звуків для лаунчера / веб-плеєра.
Все синтезується з нуля, ніяких семплів.

pip install numpy scipy soundfile
python3 uisfx.py -o out/
"""

import argparse
import os

import numpy as np
from scipy import signal
import soundfile as sf

SR = 48000
rng = np.random.default_rng(12345)  # фіксований seed -> відтворювані шумові шари


# ─────────────────────────── базові блоки ───────────────────────────

def t(dur):
    return np.arange(int(SR * dur)) / SR


def sine(freq, dur):
    return np.sin(2 * np.pi * freq * t(dur))


def sweep(f0, f1, dur, curve="exp"):
    """Гліссандо. Фаза = інтеграл частоти, інакше буде розрив."""
    tt = t(dur)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (tt / dur)
    else:
        f = f0 + (f1 - f0) * (tt / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase)


def fm(carrier, ratio, index, dur, index_decay=6.0):
    """Проста 2-операторна FM. ratio 1.4-3.5 -> метал/дзвін."""
    tt = t(dur)
    mod = np.sin(2 * np.pi * carrier * ratio * tt) * index * np.exp(-index_decay * tt / dur)
    return np.sin(2 * np.pi * carrier * tt + mod)


def pluck(freq, dur, damp=0.996, bright=0.5):
    """Karplus-Strong. Дає 'тактильний' щипок замість стерильної синусоїди."""
    n = max(2, int(SR / freq))
    buf = rng.standard_normal(n)
    buf = lowpass(buf, 200 + bright * 8000)
    out = np.zeros(int(SR * dur))
    idx = 0
    for i in range(len(out)):
        out[i] = buf[idx]
        nxt = (idx + 1) % n
        buf[idx] = damp * 0.5 * (buf[idx] + buf[nxt])
        idx = nxt
    return out


def noise(dur):
    return rng.standard_normal(int(SR * dur))


def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (SR / 2), 0.99), btype="low")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, max(cutoff / (SR / 2), 1e-4), btype="high")
    return signal.lfilter(b, a, x)


def bandpass(x, low, high, order=2):
    b, a = signal.butter(order, [low / (SR / 2), min(high / (SR / 2), 0.99)], btype="band")
    return signal.lfilter(b, a, x)


def resonate(x, freq, q=12.0):
    """Резонансний пік — з шуму робить 'тук' з висотою."""
    b, a = signal.iirpeak(freq / (SR / 2), q)
    return signal.lfilter(b, a, x)


# ─────────────────────────── обгортки ───────────────────────────

def env(dur, attack=0.002, curve=5.0):
    """Швидка атака + експоненційний спад. curve більший = коротший хвіст."""
    tt = t(dur)
    a = np.clip(tt / max(attack, 1e-6), 0, 1)
    d = np.exp(-curve * tt / dur)
    return a * d


def ar(dur, attack, release, curve=3.0):
    tt = t(dur)
    a = np.clip(tt / max(attack, 1e-6), 0, 1)
    r = np.ones_like(tt)
    rs = int(SR * (dur - release))
    if rs < len(tt):
        k = (tt[rs:] - tt[rs]) / max(release, 1e-6)
        r[rs:] = np.exp(-curve * k)
    return a * r


# ─────────────────────────── обробка ───────────────────────────

def pad(x, dur):
    n = int(SR * dur)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*layers):
    n = max(len(l) for l in layers)
    out = np.zeros(n)
    for l in layers:
        out[: len(l)] += l
    return out


def tail(x, amount=0.16, decay=0.09):
    """Мікро-реверб. Дає 'простір', але не робить звук довгим."""
    n = len(x)
    ir_len = int(SR * decay)
    ir = rng.standard_normal(ir_len) * np.exp(-6 * np.arange(ir_len) / ir_len)
    ir = highpass(ir, 400)
    ir /= np.max(np.abs(ir)) + 1e-9
    wet = signal.fftconvolve(x, ir)[: n + ir_len]
    wet /= np.max(np.abs(wet)) + 1e-9
    out = np.pad(x, (0, len(wet) - n)) + wet * amount
    return out


def finish(x, peak_db=-6.0, fade_ms=3.0):
    """Нормалізація + фейди. Без фейдів на краях будуть клацання."""
    x = np.asarray(x, dtype=np.float64)
    x -= np.mean(x)                       # прибрати DC
    x = highpass(x, 60)                   # прибрати субнизи, на ТВ-динаміках лише гуде
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * (10 ** (peak_db / 20))
    f = max(1, int(SR * fade_ms / 1000))
    if len(x) > 2 * f:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    return x


def trim(x, thresh_db=-60.0):
    """Обрізати тишу в хвості — важливо для латентності й розміру."""
    thr = 10 ** (thresh_db / 20)
    nz = np.where(np.abs(x) > thr)[0]
    return x[: nz[-1] + 1] if len(nz) else x


# ─────────────────────────── рецепти ───────────────────────────
# Формула майже кожного "дорогого" UI-звуку:
#   транзієнт (шум, 5-10 мс) + тон з висотою (60-120 мс) + мікро-хвіст

def s_focus():
    """Тік при переміщенні фокуса. Найтихіший, чується сотні разів."""
    d = 0.045
    click = resonate(noise(0.006), 2600, q=6) * env(0.006, 0.0004, 9)
    body = sine(1180, d) * env(d, 0.0015, 7) * 0.55
    body += sine(2360, d) * env(d, 0.001, 11) * 0.12   # обертон для 'скла'
    return finish(mix(pad(click, d), body), peak_db=-15)


def s_select():
    """Підтвердження. Висхідний інтервал = 'відкриття'."""
    d = 0.13
    click = resonate(noise(0.008), 1800, q=5) * env(0.008, 0.0004, 8) * 0.7
    body = sweep(740, 1108, 0.09) * env(0.09, 0.002, 5)        # ~квінта вгору
    shine = fm(2200, 2.0, 2.2, 0.07, 9) * env(0.07, 0.001, 10) * 0.16
    return finish(tail(mix(pad(click, d), pad(body, d), pad(shine, d)), 0.14), peak_db=-6)


def s_back():
    """Скасування — дзеркало select, спадний інтервал."""
    d = 0.12
    click = resonate(noise(0.007), 1200, q=5) * env(0.007, 0.0004, 8) * 0.6
    body = sweep(880, 587, 0.085) * env(0.085, 0.002, 5)
    return finish(tail(mix(pad(click, d), pad(body, d)), 0.10), peak_db=-9)


def s_error():
    """Дисонанс, нижче й довше. Має зупиняти, не дратувати."""
    d = 0.26
    a = sine(311, 0.2) * ar(0.2, 0.004, 0.14, 4)
    b = sine(330, 0.2) * ar(0.2, 0.004, 0.14, 4) * 0.8    # биття ~19 Гц
    buzz = fm(311, 1.41, 3.0, 0.18, 4) * env(0.18, 0.003, 4) * 0.22
    return finish(mix(pad(a, d), pad(b, d), pad(buzz, d)), peak_db=-7)


def s_toggle_on():
    d = 0.09
    thock = resonate(noise(0.012), 900, q=9) * env(0.012, 0.0005, 7)
    body = pluck(660, 0.07, damp=0.992, bright=0.4) * env(0.07, 0.001, 6) * 0.8
    return finish(mix(pad(thock, d), pad(body, d)), peak_db=-9)


def s_toggle_off():
    d = 0.09
    thock = resonate(noise(0.012), 700, q=9) * env(0.012, 0.0005, 7)
    body = pluck(494, 0.07, damp=0.990, bright=0.3) * env(0.07, 0.001, 6) * 0.8
    return finish(mix(pad(thock, d), pad(body, d)), peak_db=-10)


def s_open():
    """Розкриття картки / вхід у деталі."""
    d = 0.22
    air = bandpass(noise(0.16), 1200, 7000) * ar(0.16, 0.05, 0.10, 3) * 0.30
    body = sweep(392, 784, 0.16, "exp") * env(0.16, 0.008, 4) * 0.7
    return finish(tail(mix(pad(air, d), pad(body, d)), 0.18), peak_db=-8)


def s_close():
    d = 0.18
    air = bandpass(noise(0.13), 900, 5000) * ar(0.13, 0.006, 0.11, 4) * 0.28
    body = sweep(659, 330, 0.13, "exp") * env(0.13, 0.003, 5) * 0.7
    return finish(mix(pad(air, d), pad(body, d)), peak_db=-10)


def s_start():
    """Сплеш при старті лаунчера. Єдиний, якому можна бути довгим."""
    d = 0.9
    notes = [(392, 0.00), (587, 0.07), (784, 0.14), (1175, 0.21)]
    layers = []
    for f, off in notes:
        v = fm(f, 1.0, 1.4, 0.6, 5) * env(0.6, 0.004, 4) * 0.5
        layers.append(np.pad(v, (int(SR * off), 0)))
    sub = sine(98, 0.5) * env(0.5, 0.01, 5) * 0.25
    layers.append(sub)
    return finish(tail(mix(*[pad(l, d) for l in layers]), 0.28, 0.28), peak_db=-4)


SOUNDS = {
    "focus": s_focus,
    "select": s_select,
    "back": s_back,
    "error": s_error,
    "toggle_on": s_toggle_on,
    "toggle_off": s_toggle_off,
    "open": s_open,
    "close": s_close,
    "start": s_start,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="out")
    ap.add_argument("--only", nargs="*", help="генерувати лише ці")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    names = args.only or list(SOUNDS)

    for name in names:
        x = trim(SOUNDS[name]())
        path = os.path.join(args.out, f"{name}.wav")
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
        print(f"{name:12s} {len(x)/SR*1000:6.1f} ms  {os.path.getsize(path)/1024:6.1f} KB")


if __name__ == "__main__":
    main()