#!/usr/bin/env python3
"""
tvsfx.py — генератор звуку для Android TV застосунку про кіно.

Два різні світи в одному файлі:

  UI      — короткі події (фокус, вибір, play). Ті самі принципи, що в
            uisfx.py: транзієнт + тон + хвіст. Але стерео і з реальним залом.
  AMBIENT — довгі петлі, які тихо грають під інтерфейсом. Це те, що робить
            лаунчер «кінотеатром», а не списком іконок.

Головне правило міксу: бед живе на -30 dBFS RMS, UI б'є на -6..-18 dBFS peak.
Бед не має бути помітним — його помічають лише коли вимкнути.

    uv sync
    uv run tvsfx.py -o out/
    uv run tvsfx.py -o out/ --only play logo amb_home
"""

import argparse
import json
import os
import time

import numpy as np
import soundfile as sf

import dsp as d
from dsp import SR

# ─────────────────────────── зали ───────────────────────────
# IR рахуються один раз і перевикористовуються — це найдорожча операція тут.

_IR = {}
_SPACES = {
    "room":   dict(decay=0.75, predelay=0.006, damp=5000, diffusion=0.008, seed=3),
    "hall":   dict(decay=2.60, predelay=0.020, damp=4000, diffusion=0.016, seed=7),
    "cinema": dict(decay=4.80, predelay=0.032, damp=3200, diffusion=0.026, seed=11),
    "bed":    dict(decay=6.50, predelay=0.045, damp=2600, diffusion=0.040, seed=17),
}


def ir(name):
    if name not in _IR:
        _IR[name] = d.make_ir(**_SPACES[name])
    return _IR[name]


# ─────────────────────────── допоміжні ───────────────────────────

def band_sweep(dur, f0, f1, bands=18, seed=5, width=1.7):
    """Шум із смугою, що їде по спектру. Основа будь-якого whoosh.

    Чесний time-varying фільтр тут зайвий: сума статичних смуг із рухомим
    гаусовим вікном звучить так само, а рахується миттєво.
    """
    x = d.noise(dur, seed)
    tt = d.t(dur) / dur
    out = np.zeros_like(x)
    for i, f in enumerate(np.geomspace(f0, f1, bands)):
        pos = i / (bands - 1)
        out += d.bandpass(x, f / width, f * width, 2) * np.exp(-((tt - pos) ** 2) / (2 * (1.1 / bands) ** 2))
    return out


def stereo_air(dur, low, high, seed=0):
    """Повітря з різним шумом у каналах — джерело ширини, яка не розвалює моно."""
    l = d.bandpass(d.noise(dur, seed), low, high, 2)
    r = d.bandpass(d.noise(dur, seed + 100), low, high, 2)
    return np.column_stack([l, r])


# ═══════════════════════════ UI ═══════════════════════════

def s_focus():
    """Рух фокуса по постерах. Найтихіший звук у системі — чується сотні разів
    за сесію, тому ні хвоста, ні низу, ні характеру. Тільки «є контакт»."""
    dur = 0.05
    tick = d.resonate(d.noise(0.005, 21), 3100, q=7) * d.env(0.005, 0.0004, 9)
    body = d.sine(1245, dur) * d.env(dur, 0.0012, 8) * 0.5
    body += d.sine(2490, dur) * d.env(dur, 0.0008, 13) * 0.10   # обертон для «скла»
    return d.finish(d.mix(d.pad(tick, dur), body), peak_db=-17, hp=200, fade_ms=2)


def s_nav_edge():
    """Упор у край ряду. Глухо і без резонансу — «далі нічого немає»."""
    dur = 0.09
    thud = d.resonate(d.noise(0.014, 22), 220, q=4) * d.env(0.014, 0.0006, 6)
    body = d.sine(174, dur) * d.env(dur, 0.002, 9) * 0.8
    return d.finish(d.mix(d.pad(thud, dur), body), peak_db=-16, hp=90, lp=1800)


def s_key_tap():
    """Екранна клавіатура пошуку. Абсолютно сухо: реверб на 30 символах підряд
    перетворюється на кашу."""
    dur = 0.028
    tick = d.resonate(d.noise(0.004, 23), 2200, q=9) * d.env(0.004, 0.0003, 10)
    body = d.sine(880, dur) * d.env(dur, 0.0008, 12) * 0.35
    return d.finish(d.mix(d.pad(tick, dur), body), peak_db=-20, hp=250, fade_ms=1.5)


def s_select():
    """Вибір картки. Висхідна квінта = «відкриття», кімната мала — рішення
    ще не змінює екран."""
    dur = 0.30
    click = d.resonate(d.noise(0.008, 24), 2000, q=5) * d.env(0.008, 0.0004, 8) * 0.75
    body = d.sweep(740, 1108, 0.10) * d.env(0.10, 0.002, 5)
    shine = d.fm(2200, 2.0, 2.2, 0.08, 9) * d.env(0.08, 0.001, 10) * 0.18
    dry = d.mix(d.pad(click, 0.12), d.pad(body, 0.12), d.pad(shine, 0.12))
    return d.finish(d.pad(d.shimmer(dry, ir("room"), wet=0.30), dur), peak_db=-10, hp=120)


def s_back():
    """Дзеркало select: спадна квінта, темніше, менше блиску."""
    dur = 0.28
    click = d.resonate(d.noise(0.007, 25), 1300, q=5) * d.env(0.007, 0.0004, 8) * 0.6
    body = d.sweep(880, 587, 0.095) * d.env(0.095, 0.002, 5)
    dry = d.mix(d.pad(click, 0.11), d.pad(body, 0.11))
    x = d.reverb(dry, ir("room"), wet=0.26)
    return d.finish(d.pad(x, dur), peak_db=-12, hp=110, lp=7000)


def s_open():
    """Постер розгортається у сторінку фільму.

    Повітря, що розлітається в боки + висхідна квінта + саб-підйом.
    Тут уперше з'являється ширина: екран став більшим — простір теж."""
    dur = 0.85
    air = stereo_air(0.30, 700, 9000, seed=31) * d.ar(0.30, 0.06, 0.20, 3)[:, None] * 0.30
    body = d.sweep(330, 660, 0.28, "exp") * d.env(0.28, 0.010, 3.5) * 0.75
    lift = d.sweep(48, 96, 0.30, "exp") * d.ar(0.30, 0.05, 0.22, 3) * 0.45
    dry = d.mix(air, d.pad(body, 0.30), d.pad(lift, 0.30))
    x = d.shimmer(d.widen(dry, 1.4), ir("hall"), wet=0.34)
    return d.finish(d.pad(x, dur), peak_db=-8, hp=45)


def s_close():
    """Згортання назад до сітки. Коротше за open — вихід завжди швидший
    за вхід, інакше інтерфейс здається в'язким."""
    dur = 0.50
    air = stereo_air(0.20, 500, 6000, seed=32) * d.ar(0.20, 0.008, 0.17, 4)[:, None] * 0.26
    body = d.sweep(620, 310, 0.20, "exp") * d.env(0.20, 0.004, 4) * 0.7
    dry = d.mix(air, d.pad(body, 0.20))
    x = d.reverb(d.widen(dry, 1.25), ir("hall"), wet=0.24)
    return d.finish(d.pad(x, dur), peak_db=-11, hp=60, lp=9000)


def s_play():
    """Головний звук застосунку. Момент, заради якого все й вмикали.

    Три шари: суб, що падає (фізика — щось велике зрушило), яскравий транзієнт
    (механіка — воно клацнуло) і шимер-цвітіння (простір — зал розкрився).
    exciter обов'язковий: без гармонік саб не існує на динаміках телевізора."""
    dur = 1.15
    hit = d.resonate(d.noise(0.012, 41), 4200, q=4) * d.env(0.012, 0.0004, 7) * 0.55
    sub = d.sweep(78, 36, 0.40, "exp") * d.ar(0.40, 0.004, 0.34, 3) * 1.0
    bell = d.fm(440, 2.0, 3.0, 0.35, 7) * d.env(0.35, 0.002, 5) * 0.45
    lift = d.mix(*[d.at(d.sine(f, 0.30) * d.env(0.30, 0.006, 4) * a, o, 0.42)
                   for f, a, o in [(660, 0.22, 0.02), (880, 0.16, 0.05), (1320, 0.10, 0.08)]])
    dry = d.mix(d.pad(hit, 0.42), d.pad(sub, 0.42), d.pad(bell, 0.42), lift)
    dry = d.exciter(dry, 32, 110, amount=0.7)
    x = d.shimmer(d.widen(d.st(dry), 1.35), ir("cinema"), wet=0.30)
    return d.finish(d.pad(x, dur), peak_db=-5, hp=30, drive=1.3)


def s_pause():
    """Зал закривається. Спадна терція під фільтром — рух зупинився,
    але нічого не скасовано."""
    dur = 0.45
    thock = d.resonate(d.noise(0.016, 42), 520, q=6) * d.env(0.016, 0.0008, 6) * 0.7
    body = d.sweep(440, 330, 0.16) * d.env(0.16, 0.004, 4) * 0.8
    dry = d.mix(d.pad(thock, 0.18), d.pad(body, 0.18))
    x = d.reverb(dry, ir("hall"), wet=0.20)
    return d.finish(d.pad(x, dur), peak_db=-12, hp=70, lp=4000)


def s_stop():
    """Повна зупинка: сухий низький удар, хвіст обрубаний."""
    dur = 0.30
    thud = d.resonate(d.noise(0.02, 43), 130, q=3.5) * d.env(0.02, 0.001, 5)
    body = d.mix(d.sine(110, 0.16) * d.env(0.16, 0.003, 7) * 0.9,
                 d.sine(165, 0.10) * d.env(0.10, 0.002, 9) * 0.25)
    dry = d.mix(d.pad(thud, 0.18), d.pad(body, 0.18))
    x = d.reverb(dry, ir("room"), wet=0.14)
    return d.finish(d.pad(x, dur), peak_db=-11, hp=45, lp=3000)


def s_seek():
    """Тік перемотки. Може повторюватись 10 разів на секунду — сухо і коротко."""
    dur = 0.045
    tick = d.resonate(d.noise(0.005, 44), 1600, q=10) * d.env(0.005, 0.0003, 9)
    body = d.sine(1760, dur) * d.env(dur, 0.0006, 10) * 0.32
    return d.finish(d.mix(d.pad(tick, dur), body), peak_db=-19, hp=300, fade_ms=2)


def s_volume():
    """Крок гучності. Ще тихіше за focus — інакше при зміні гучності
    користувач чує сам звук, а не результат."""
    dur = 0.035
    tick = d.resonate(d.noise(0.006, 45), 2800, q=14) * d.env(0.006, 0.0003, 8)
    body = d.sine(1660, dur) * d.env(dur, 0.0006, 11) * 0.25
    return d.finish(d.mix(d.pad(tick, dur), body), peak_db=-21, hp=400, fade_ms=2)


def s_error():
    """Помилка. Низько, з биттям ~7 Гц і без верхів.

    Має зупиняти, не дратувати: жодного різкого «біп», уся енергія в
    середині, де вухо чутливе, але не болить."""
    dur = 0.60
    a = d.sine(116.5, 0.34) * d.ar(0.34, 0.005, 0.26, 3.5)
    b = d.sine(123.5, 0.34) * d.ar(0.34, 0.005, 0.26, 3.5) * 0.85   # биття 7 Гц
    buzz = d.fm(233, 1.41, 2.6, 0.30, 4) * d.env(0.30, 0.004, 4) * 0.25
    dry = d.mix(d.pad(a, 0.36), d.pad(b, 0.36), d.pad(buzz, 0.36))
    x = d.reverb(dry, ir("room"), wet=0.18)
    return d.finish(d.pad(x, dur), peak_db=-9, hp=70, lp=2600)


def s_toggle_on():
    dur = 0.20
    thock = d.resonate(d.noise(0.012, 46), 950, q=9) * d.env(0.012, 0.0005, 7)
    body = d.pluck(660, 0.09, damp=0.992, bright=0.45, seed=2) * d.env(0.09, 0.001, 6) * 0.85
    dry = d.mix(d.pad(thock, 0.10), d.pad(body, 0.10))
    return d.finish(d.pad(d.reverb(dry, ir("room"), wet=0.16), dur), peak_db=-13, hp=100)


def s_toggle_off():
    dur = 0.20
    thock = d.resonate(d.noise(0.012, 47), 700, q=9) * d.env(0.012, 0.0005, 7)
    body = d.pluck(494, 0.09, damp=0.990, bright=0.30, seed=3) * d.env(0.09, 0.001, 6) * 0.85
    dry = d.mix(d.pad(thock, 0.10), d.pad(body, 0.10))
    return d.finish(d.pad(d.reverb(dry, ir("room"), wet=0.14), dur), peak_db=-14, hp=100, lp=6000)


def s_notice():
    """Нова серія / рекомендація. Два дзвони вгору і довге цвітіння —
    приємна новина, не тривога."""
    dur = 1.40
    n1 = d.fm(784, 2.0, 2.4, 0.30, 8) * d.env(0.30, 0.002, 5) * 0.8
    n2 = d.fm(1175, 2.0, 2.0, 0.30, 8) * d.env(0.30, 0.002, 5) * 0.55
    dry = d.mix(d.at(n1, 0.0, 0.42), d.at(n2, 0.085, 0.42))
    x = d.shimmer(d.widen(d.st(dry), 1.3), ir("hall"), wet=0.38)
    return d.finish(d.pad(x, dur), peak_db=-9, hp=140)


def s_download_done():
    """Завантаження завершено — висхідне тризвуччя, найпозитивніший звук набору."""
    dur = 1.30
    notes = [(587.33, 0.00, 0.7), (783.99, 0.075, 0.6), (1174.66, 0.150, 0.5)]
    dry = d.mix(*[d.at(d.fm(f, 1.0, 1.6, 0.32, 6) * d.env(0.32, 0.003, 5) * a, o, 0.50)
                  for f, o, a in notes])
    x = d.shimmer(d.widen(d.st(dry), 1.25), ir("hall"), wet=0.32)
    return d.finish(d.pad(x, dur), peak_db=-9, hp=120)


def s_paired():
    """Приставку прив'язано до акаунта по QR — два голоси сходяться в центр.

    Звук пари має читатись саме як «двоє стали одним», інакше він нічим не
    відрізняється від download_done. Тому головне тут не тембр, а панорама:
    дві ноти починають рознесеними по краях і їдуть назустріч, а третя вже
    стоїть посередині — на ній вони зустрілись.

    Коротше за download_done: це підтвердження, а не свято. Рух у панорамі в
    моно зникає, тому гармонія несе те саме сама по собі — квінта D5+A5, що
    розв'язується в D6.
    """
    dur = 1.05

    def travel(x, start, end):
        """Джерело їде по панорамі рівною потужністю: -1 ліво, +1 право."""
        p = np.linspace(start, end, len(x))
        ang = (p + 1) * np.pi / 4
        return np.column_stack([x * np.cos(ang), x * np.sin(ang)])

    low = d.fm(587.33, 1.0, 1.5, 0.34, 6) * d.env(0.34, 0.003, 5) * 0.62
    high = d.fm(880.00, 1.0, 1.5, 0.34, 6) * d.env(0.34, 0.003, 5) * 0.50
    # Довша за обидві: те, на чому вони зупинились, має триматись довше за рух.
    meet = d.fm(1174.66, 1.0, 1.3, 0.44, 5) * d.env(0.44, 0.004, 4) * 0.46

    dry = d.mix(
        d.at(travel(low, -0.8, 0.0), 0.000, 0.50),
        d.at(travel(high, 0.8, 0.0), 0.055, 0.50),
        d.at(d.st(meet), 0.150, 0.60),
    )
    x = d.shimmer(d.widen(d.st(dry), 1.2), ir("hall"), wet=0.34)
    return d.finish(d.pad(x, dur), peak_db=-9, hp=130)


def s_whoosh():
    """Перехід між екранами. Смуга їде вгору, панорама — зліва направо.

    Рух у панорамі важливіший за сам тембр: саме він читається як
    «екран поїхав», а не «щось зашуміло»."""
    dur = 0.70
    sw = band_sweep(0.34, 260, 7500, bands=20, seed=51)
    sw *= d.ar(0.34, 0.05, 0.24, 2.5)
    p = np.linspace(-0.85, 0.85, len(sw))          # рух джерела
    ang = (p + 1) * np.pi / 4
    body = np.column_stack([sw * np.cos(ang), sw * np.sin(ang)])
    sub = d.sweep(120, 45, 0.34, "exp") * d.ar(0.34, 0.04, 0.26, 3) * 0.35
    dry = d.mix(body, d.pad(sub, 0.34))
    x = d.reverb(dry, ir("hall"), wet=0.28)
    return d.finish(d.pad(x, dur), peak_db=-10, hp=50)


def s_logo():
    """Сплеш при старті. Єдиний звук, якому дозволено бути довгим і гучним.

    Драматургія на 4 секунди: вдих (шум наростає) -> удар (саб падає) ->
    розкриття (мінорний акорд розпускається вгору в шимері)."""
    dur = 4.0
    hit_at = 0.70

    breath = stereo_air(hit_at, 300, 8000, seed=61)
    breath *= (np.linspace(0, 1, len(breath)) ** 2.6)[:, None] * 0.34

    hit = d.resonate(d.noise(0.02, 62), 3000, q=3) * d.env(0.02, 0.0004, 6) * 0.5
    sub = d.sweep(92, 31, 0.90, "exp") * d.ar(0.90, 0.004, 0.80, 2.6)
    impact = d.exciter(d.mix(d.pad(hit, 0.95), d.pad(sub, 0.95)), 28, 110, amount=0.85)

    chord = [(110, 0.00, 0.30), (164.81, 0.05, 0.26), (261.63, 0.10, 0.24),
             (329.63, 0.16, 0.20), (493.88, 0.24, 0.14), (659.25, 0.34, 0.10)]
    bloom = d.mix(*[d.at(d.fm(f, 1.0, 1.3, 1.5, 4) * d.ar(1.5, 0.012, 1.2, 3) * a, o, 1.9)
                    for f, o, a in chord])

    dry = d.mix(breath, d.at(impact, hit_at, dur), d.at(d.st(bloom), hit_at, dur))
    x = d.shimmer(d.widen(dry, 1.45), ir("cinema"), wet=0.42)
    return d.finish(d.pad(x, dur), peak_db=-3, hp=28, drive=1.25)


# ═══════════════════════════ AMBIENT ═══════════════════════════

def bed(dur, root, chord, *, dark=380, bright=2400, air_band=(2200, 9000),
        air_amt=0.10, sub_amt=0.55, body=0.85, warmth=0.7, rolloff=1.15,
        tilt_db=-1.5, wet=0.34, loud=-34.0, events=(), seed=0):
    """Амбієнт-петля.

    Кожен шар циклічний за побудовою: частоти притягнуті до сітки 1/dur,
    LFO роблять ціле число обертів за петлю, шум згенерований у спектрі,
    реверб — циркулярний. Тому стик не потребує кросфейду взагалі.

    Живість дають три незалежні речі:
      - розстройка ±7 центів між парами голосів -> повільні биття;
      - різні LFO на гучність кожного голосу -> акорд «дихає» нерівномірно;
      - кросфейд темного і яскравого фільтра -> хвиля відкриття тембру.
    """
    n = int(SR * dur)
    layers = []

    # саб — завжди в моно: рознесений низ на саундбарі перетворюється на гул.
    # exciter обов'язковий: вбудований динамік ТВ нижче ~150 Гц не грає нічого,
    # і без гармонічної «тіні» весь цей шар для більшості людей просто не існує.
    r = d.snap(root, dur)
    s = (d.harmonics(r, dur, n_harm=3, rolloff=2.6, seed=seed + 1)
         + d.harmonics(d.snap(r * 1.004, dur), dur, n_harm=2, rolloff=3.0, seed=seed + 2) * 0.6)
    s = s * (0.72 + 0.28 * d.uni(d.lfo(2, dur))) * sub_amt
    layers.append(d.st(d.exciter(s, r * 0.7, r * 2.2, amount=warmth)))

    # пад — пари розстроєних голосів, рознесені по панорамі
    voices = []
    for i, f in enumerate(chord):
        f = d.snap(f, dur)
        amp = 0.9 / (1 + i * 0.45)                      # верхні голоси тихіші
        breathe = 0.55 + 0.45 * d.uni(d.lfo(2 + i, dur, phase=i * 1.1))
        l = d.harmonics(f, dur, n_harm=18, rolloff=rolloff, seed=seed + 10 + i, detune=-7)
        rr = d.harmonics(f, dur, n_harm=18, rolloff=rolloff, seed=seed + 40 + i, detune=+7)
        voices.append(np.column_stack([l, rr]) * (amp * breathe)[:, None])
    pad_ = d.mix(*voices)
    pad_ = d.morph_lp(pad_, dark, bright, d.uni(d.lfo(3, dur, phase=0.7)))
    layers.append(pad_ * body)

    # повітря — різний шум у каналах, дві швидкості дихання
    air = np.column_stack([d.noise_loop(dur, seed + 70), d.noise_loop(dur, seed + 71)])
    air = d.pfilt(air, lambda x: d.bandpass(x, *air_band, 2))
    air *= (0.35 + 0.65 * d.uni(d.lfo(2, dur)) * d.uni(d.lfo(5, dur, phase=2.0)))[:, None]
    layers.append(air * air_amt)

    # тон кімнати — низький шум, майже нечутний, але без нього пад «у вакуумі»
    room = np.column_stack([d.noise_loop(dur, seed + 80), d.noise_loop(dur, seed + 81)])
    room = d.pfilt(room, lambda x: d.lowpass(x, 260, 3))
    layers.append(room * (0.5 + 0.5 * d.uni(d.lfo(1, dur)))[:, None] * 0.06)

    x = d.mix(*[l[:n] for l in layers])
    x = d.creverb(x, ir("bed"), wet=wet)

    # разові події поверх — їхній хвіст загортається на початок петлі
    for i, (at_s, freq, amp) in enumerate(events):
        e = d.fm(freq, 2.0, 1.8, 1.2, 6) * d.ar(1.2, 0.02, 1.0, 3) * amp
        e = d.shimmer(d.pan(e, 0.45 if i % 2 else -0.45), ir("bed"), wet=0.5)
        x = x + d.loopify(d.at(e, at_s, dur + len(e) / SR), dur)

    x = d.tilt(x, tilt_db)
    return d.finish_loop(x, loud=loud)


def a_home():
    """Головний екран. Am add9 — тепло, нейтрально, без сюжету.
    Тут людина проводить найбільше часу, тому нічого, що привертає увагу."""
    return bed(30.0, 55.0, [110.0, 164.81, 261.63, 329.63, 493.88],
               dark=420, bright=2900, air_amt=0.13, sub_amt=0.55, warmth=0.75,
               tilt_db=-1.6, loud=-33.0, seed=100,
               events=[(6.5, 659.25, 0.16), (17.2, 987.77, 0.12), (25.0, 493.88, 0.14)])


def a_details():
    """Сторінка фільму. Dm7, нижче і темніше: контент став конкретним,
    з'явилась вага. Верхів майже немає — під трейлером вони б заважали."""
    return bed(24.0, 73.42, [110.0, 146.83, 220.0, 261.63, 349.23],
               dark=340, bright=1900, air_band=(1800, 8000), air_amt=0.24,
               sub_amt=0.60, warmth=0.9, tilt_db=-2.6, wet=0.38, loud=-34.0, seed=200,
               events=[(9.0, 220.0, 0.20), (19.5, 174.61, 0.16)])


def a_search():
    """Пошук. Fmaj7#11 — світліше й прозоріше, більше повітря.
    Стан «шукаю» має відчуватись легшим за стан «дивлюсь»."""
    return bed(20.0, 87.31, [130.81, 220.0, 329.63, 493.88, 659.25],
               dark=520, bright=4200, air_band=(3000, 12000), air_amt=0.18,
               sub_amt=0.55, warmth=0.6, tilt_db=-2.4, wet=0.30, loud=-35.0, seed=300,
               events=[(3.3, 1318.51, 0.10), (8.1, 987.77, 0.09),
                       (13.9, 1567.98, 0.08), (17.5, 1174.66, 0.09)])


def a_player_idle():
    """Пауза / простій плеєра. Майже порожньо: саб, тон кімнати і один
    далекий удар за 32 секунди. Це вже не музика, це тиша з текстурою."""
    return bed(32.0, 65.41, [98.0, 130.81, 155.56],
               dark=300, bright=1600, air_band=(1500, 6500), air_amt=0.17,
               sub_amt=0.70, warmth=0.95, tilt_db=-3.0, wet=0.40, loud=-37.0, seed=400,
               events=[(14.0, 130.81, 0.22)])


# ─────────────────────────── реєстр ───────────────────────────
# gain — рекомендована гучність у SoundPool.play() / setVolume().
# Пік у файлі задає тембровий запас, gain — місце звуку в ієрархії.

UI = {
    "focus":         (s_focus, 0.35),
    "nav_edge":      (s_nav_edge, 0.45),
    "key_tap":       (s_key_tap, 0.30),
    "select":        (s_select, 0.70),
    "back":          (s_back, 0.55),
    "open":          (s_open, 0.75),
    "close":         (s_close, 0.60),
    "play":          (s_play, 1.00),
    "pause":         (s_pause, 0.65),
    "stop":          (s_stop, 0.65),
    "seek":          (s_seek, 0.40),
    "volume":        (s_volume, 0.45),
    "error":         (s_error, 0.80),
    "toggle_on":     (s_toggle_on, 0.55),
    "toggle_off":    (s_toggle_off, 0.55),
    "notice":        (s_notice, 0.85),
    "download_done": (s_download_done, 0.80),
    "paired":        (s_paired, 0.75),
    "whoosh":        (s_whoosh, 0.70),
    "logo":          (s_logo, 1.00),
}

BEDS = {
    "amb_home":        (a_home, 0.55),
    "amb_details":     (a_details, 0.50),
    "amb_search":      (a_search, 0.50),
    "amb_player_idle": (a_player_idle, 0.45),
}

ALL = {**UI, **BEDS}


# ─────────────────────────── запис ───────────────────────────

def write(path_base, x, loop, force_wav=False):
    """UI -> WAV PCM16 (SoundPool не вміє нічого іншого дешево).
    Петлі -> OGG Vorbis: 30 с стерео це 5.5 МБ у WAV і ~380 КБ в OGG.
    Якщо канали ідентичні — пишемо моно, це мінус половина розміру."""
    if x.ndim == 2 and np.max(np.abs(x[:, 0] - x[:, 1])) < 2e-4:
        x = x[:, 0]
    if loop and not force_wav and "OGG" in sf.available_formats():
        path = path_base + ".ogg"
        sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    else:
        path = path_base + ".wav"
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
    return path


def db(v):
    return 20 * np.log10(v) if v > 0 else -120.0


def demo(dur=22.0):
    """Демо-мікс: бед + типовий сценарій користувача поверх нього.

    Єдиний спосіб перевірити головне рішення набору — чи бед на -33 LUFS
    не забиває UI і чи UI не збиває бед. Окремі файли цього не покажуть.
    """
    n = int(SR * dur)
    home, det = a_home(), a_details()
    base = np.vstack([home] * (n // len(home) + 1))[:n]          # петля крутиться
    x = base.copy()
    x[int(SR * 12.0):] *= np.linspace(1, 0, n - int(SR * 12.0))[:, None]  # кросфейд у details
    d2 = np.vstack([det] * (n // len(det) + 1))[:n]
    d2[:int(SR * 12.0)] = 0
    d2[int(SR * 12.0):] *= np.linspace(0, 1, n - int(SR * 12.0))[:, None]
    x += d2

    # сценарій: походив по сітці -> відкрив фільм -> увімкнув -> поставив паузу
    script = [(0.4, "logo"), (4.6, "focus"), (5.0, "focus"), (5.35, "focus"),
              (5.7, "focus"), (6.2, "select"), (6.35, "whoosh"), (7.8, "focus"),
              (8.2, "focus"), (8.9, "back"), (10.0, "focus"), (10.4, "focus"),
              (11.2, "select"), (11.35, "open"), (14.5, "play"), (17.5, "pause"),
              (18.6, "focus"), (19.2, "volume"), (19.45, "volume"), (19.7, "volume"),
              (20.4, "notice")]
    for at_s, name in script:
        fn, gain = UI[name]
        x += d.at(d.st(d.trim(fn())) * gain, at_s, dur)
    return d.norm_lufs(x, -22.0, ceiling_db=-3.0)


def main():
    ap = argparse.ArgumentParser(description="UI + амбієнт для Android TV")
    ap.add_argument("-o", "--out", default="out")
    ap.add_argument("--only", nargs="*", help="генерувати лише ці")
    ap.add_argument("--ui", action="store_true", help="лише UI-звуки")
    ap.add_argument("--beds", action="store_true", help="лише амбієнт-петлі")
    ap.add_argument("--wav-beds", action="store_true", help="петлі у WAV замість OGG")
    ap.add_argument("--demo", action="store_true",
                    help="звести demo.wav: бед + сценарій UI поверх нього")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    if args.demo:
        x = demo()
        p = os.path.join(args.out, "demo.wav")
        sf.write(p, x.astype(np.float32), SR, subtype="PCM_16")
        print(f"demo.wav  {len(x)/SR:.1f} с  {d.lufs(x):.1f} LUFS  -> {p}")
        return
    if args.only:
        names = args.only
    elif args.ui:
        names = list(UI)
    elif args.beds:
        names = list(BEDS)
    else:
        names = list(ALL)

    manifest = []
    print(f"{'звук':16s} {'мс':>8s} {'кан':>4s} {'пік':>7s} {'LUFS':>6s} {'розмір':>9s}")
    print("─" * 62)
    for name in names:
        if name not in ALL:
            print(f"{name:16s} — немає такого рецепта")
            continue
        fn, gain = ALL[name]
        loop = name in BEDS
        t0 = time.time()
        x = fn()
        if not loop:
            x = d.trim(x)                       # тишу в хвості не тримаємо: латентність і розмір
        path = write(os.path.join(args.out, name), x, loop, args.wav_beds)
        ms = len(x) / SR * 1000
        kb = os.path.getsize(path) / 1024
        ch = 1 if x.ndim == 1 else 2
        peak, loud = db(np.max(np.abs(x))), d.lufs(x)
        print(f"{name:16s} {ms:8.1f} {ch:4d} {peak:6.1f}d {loud:6.1f}  {kb:8.1f}K"
              f"  {time.time() - t0:4.1f}s")
        manifest.append(dict(name=name, file=os.path.basename(path), ms=round(ms, 1),
                             channels=ch, sample_rate=SR, loop=loop,
                             peak_dbfs=round(peak, 1), lufs=round(loud, 1),
                             gain=gain))

    # маніфест зливаємо, а не перезаписуємо: інакше прогін з --only стер би
    # записи про всі інші звуки, які лежать поруч і нікуди не ділись
    mpath = os.path.join(args.out, "manifest.json")
    merged = {}
    if os.path.exists(mpath):
        with open(mpath) as f:
            merged = {e["name"]: e for e in json.load(f).get("sounds", [])}
    merged.update({e["name"]: e for e in manifest})
    ordered = [merged[n] for n in ALL if n in merged]
    with open(mpath, "w") as f:
        json.dump({"sample_rate": SR, "sounds": ordered}, f, indent=2, ensure_ascii=False)
    print(f"\n{len(manifest)} файлів -> {args.out}/ "
          f"(manifest.json: {len(ordered)} записів)")


if __name__ == "__main__":
    main()
