#!/usr/bin/env python3
"""
dsp.py — синтез-рушій для tvsfx.py.

Три речі, яких немає в uisfx.py і без яких «кіношного» звуку не буде:

1. СТЕРЕО. Все, що довше 200 мс, живе у форматі (n, 2). Ширина — це половина
   відчуття «дорого» на саундбарі.
2. ЗГОРТКОВИЙ РЕВЕРБ + ШИМЕР. Не мікро-хвіст на 90 мс, а справжній зал з
   частотно-залежним спадом: низи гудуть довше за верхи, як у реальній кімнаті.
3. ЦИРКУЛЯРНИЙ СИНТЕЗ для петель. Усе для амбієнту будується через irfft на
   сітці 1/dur: осцилятори, шум, навіть реверб — усе кратне довжині петлі.
   Тому стик петлі математично безшовний, а не «майже» — жодного кросфейду,
   жодного клацання раз на 30 секунд.
"""

from fractions import Fraction

import numpy as np
from scipy import signal

SR = 48000


# ─────────────────────────── час і сітка ───────────────────────────

def t(dur):
    return np.arange(int(SR * dur)) / SR


def snap(freq, dur):
    """Притягнути частоту до сітки 1/dur.

    Ключ до безшовних петель: якщо freq * dur — ціле, за час петлі
    вкладається рівно N періодів і кінець збігається з початком.
    Розстройка на <0.5 Гц нечутна, а стик стає ідеальним.
    """
    return max(1, round(freq * dur)) / dur


# ─────────────────────────── осцилятори ───────────────────────────

def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def sweep(f0, f1, dur, curve="exp"):
    """Гліссандо. Фаза = інтеграл частоти, інакше буде розрив."""
    tt = t(dur)
    f = f0 * (f1 / f0) ** (tt / dur) if curve == "exp" else f0 + (f1 - f0) * (tt / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def fm(carrier, ratio, index, dur, index_decay=6.0):
    """2-операторна FM. ratio 1.4-3.5 -> метал/дзвін."""
    tt = t(dur)
    mod = np.sin(2 * np.pi * carrier * ratio * tt) * index * np.exp(-index_decay * tt / dur)
    return np.sin(2 * np.pi * carrier * tt + mod)


def pluck(freq, dur, damp=0.996, bright=0.5, seed=1):
    """Karplus-Strong. Дає 'тактильний' щипок замість стерильної синусоїди."""
    rng = np.random.default_rng(seed)
    n = max(2, int(SR / freq))
    buf = lowpass(rng.standard_normal(n), 200 + bright * 8000)
    out = np.zeros(int(SR * dur))
    idx = 0
    for i in range(len(out)):
        out[i] = buf[idx]
        nxt = (idx + 1) % n
        buf[idx] = damp * 0.5 * (buf[idx] + buf[nxt])
        idx = nxt
    return out


def noise(dur, seed=None):
    return np.random.default_rng(seed).standard_normal(int(SR * dur))


def harmonics(freq, dur, n_harm=24, rolloff=1.0, odd_only=False, seed=0, detune=0.0):
    """Гармонічний осцилятор, зібраний одразу в спектрі (irfft).

    Чому не сума синусів у часі: на 30-секундній петлі це мільярди операцій.
    І головне — тут кожна гармоніка лягає точно в бін сітки 1/dur, тобто
    результат циклічний за побудовою.

    detune — розстройка в центах; дає биття між шарами, від якого пад «дихає».
    """
    n = int(SR * dur)
    spec = np.zeros(n // 2 + 1, dtype=complex)
    rng = np.random.default_rng(seed)
    f = freq * (2 ** (detune / 1200.0))
    for k in range(1, n_harm + 1):
        if odd_only and k % 2 == 0:
            continue
        bin_i = int(round(f * k * dur))
        if bin_i < 1 or bin_i >= len(spec):
            break
        # випадкова фаза: інакше всі гармоніки складуться в один пік і пад
        # клацатиме на кожному періоді
        spec[bin_i] += (1.0 / k ** rolloff) * np.exp(1j * rng.uniform(0, 2 * np.pi))
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def noise_loop(dur, seed=0):
    """Циклічний білий шум: плоский модуль спектра, випадкова фаза.

    Звичайний rng-шум на стику петлі теж не клацає — але щойно його
    відфільтруєш у смугу, стик стає чутним. Цей — циклічний після
    будь-якої фільтрації через pfilt().
    """
    n = int(SR * dur)
    rng = np.random.default_rng(seed)
    spec = np.exp(1j * rng.uniform(0, 2 * np.pi, n // 2 + 1))
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def lfo(cycles, dur, phase=0.0, shape="sin"):
    """LFO, що робить рівно `cycles` обертів за петлю -> теж циклічний."""
    ph = 2 * np.pi * cycles * np.arange(int(SR * dur)) / int(SR * dur) + phase
    if shape == "sin":
        return np.sin(ph)
    if shape == "tri":
        return signal.sawtooth(ph, 0.5)
    return signal.sawtooth(ph)


def uni(x):
    """LFO -1..1 -> 0..1."""
    return x * 0.5 + 0.5


# ─────────────────────────── фільтри ───────────────────────────
# axis=0 всюди, щоб однаково працювало на моно (n,) і стерео (n,2)

def _sos(x, sos):
    return signal.sosfilt(sos, x, axis=0)


def lowpass(x, cutoff, order=2):
    return _sos(x, signal.butter(order, min(cutoff / (SR / 2), 0.99), "low", output="sos"))


def highpass(x, cutoff, order=2):
    return _sos(x, signal.butter(order, max(cutoff / (SR / 2), 1e-4), "high", output="sos"))


def bandpass(x, low, high, order=2):
    lo, hi = max(low / (SR / 2), 1e-4), min(high / (SR / 2), 0.99)
    return _sos(x, signal.butter(order, [lo, hi], "band", output="sos"))


def resonate(x, freq, q=12.0):
    """Резонансний пік — з шуму робить 'тук' з висотою."""
    b, a = signal.iirpeak(freq / (SR / 2), q)
    return signal.lfilter(b, a, x, axis=0)


def tilt(x, db_per_oct=-3.0, pivot=1000.0):
    """Нахил спектра. -3 дБ/окт = миттєво «тепліше», без різання смуг."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = 10 ** (db_per_oct * np.log2(np.maximum(f, 20) / pivot) / 20)
    g = np.clip(g, 0, 8)
    if x.ndim == 2:
        return np.fft.irfft(np.fft.rfft(x, axis=0) * g[:, None], n, axis=0)
    return np.fft.irfft(np.fft.rfft(x) * g, n)


def pfilt(x, fn):
    """Періодична фільтрація: розмножити петлю ×3, відфільтрувати, взяти середню.

    IIR-фільтр має перехідний процес на старті. Якщо фільтрувати петлю як є,
    її початок звучить інакше за кінець -> чутний стик. Так фільтр приходить
    до стаціонару ще до потрібної ділянки.
    """
    n = len(x)
    y = fn(np.concatenate([x, x, x], axis=0))
    return y[n:2 * n]


def morph_lp(x, f_dark, f_bright, m):
    """Рух фільтра як кросфейд двох статичних копій.

    Чесний time-varying фільтр зруйнував би циклічність. Кросфейд —
    ні: добуток двох періодичних сигналів періодичний.
    """
    dark = pfilt(x, lambda s: lowpass(s, f_dark, 4))
    bright = pfilt(x, lambda s: lowpass(s, f_bright, 4))
    m = m[:, None] if x.ndim == 2 else m
    return dark * (1 - m) + bright * m


# ─────────────────────────── обгортки ───────────────────────────

def env(dur, attack=0.002, curve=5.0):
    """Швидка атака + експоненційний спад. curve більший = коротший хвіст."""
    tt = t(dur)
    return np.clip(tt / max(attack, 1e-6), 0, 1) * np.exp(-curve * tt / dur)


def ar(dur, attack, release, curve=3.0):
    tt = t(dur)
    a = np.clip(tt / max(attack, 1e-6), 0, 1)
    r = np.ones_like(tt)
    rs = int(SR * (dur - release))
    if 0 <= rs < len(tt):
        r[rs:] = np.exp(-curve * (tt[rs:] - tt[rs]) / max(release, 1e-6))
    return a * r


def swell(dur, peak=0.5, curve=2.0):
    """Симетричне наростання-спад. Для «подихів» у беді."""
    tt = t(dur) / dur
    return np.exp(-((tt - peak) ** 2) / (2 * (0.5 / curve) ** 2))


# ─────────────────────────── стерео ───────────────────────────

def st(x):
    """Моно -> стерео (n,2). Стерео пропускає як є."""
    x = np.asarray(x)
    return x if x.ndim == 2 else np.column_stack([x, x])


def mono(x):
    return x.mean(axis=1) if np.ndim(x) == 2 else x


def pan(x, p=0.0):
    """Рівнопотужна панорама, p: -1 лівий .. +1 правий."""
    a = (p + 1) * np.pi / 4
    return np.column_stack([mono(x) * np.cos(a), mono(x) * np.sin(a)])


def haas(x, ms=8.0, side="R"):
    """Мікро-затримка одного каналу. Ширина без розвалу моно-суми."""
    x = st(x)
    d = int(SR * ms / 1000)
    ch = 1 if side == "R" else 0
    y = x.copy()
    y[:, ch] = np.concatenate([np.zeros(d), x[:-d, ch]]) if d else x[:, ch]
    return y


def widen(x, amount=1.6):
    """M/S: підняти боки. >2.0 руйнує моно-сумісність — на ТВ це критично."""
    x = st(x)
    m = (x[:, 0] + x[:, 1]) * 0.5
    s = (x[:, 0] - x[:, 1]) * 0.5 * amount
    return np.column_stack([m + s, m - s])


def decorrelate(x, ms=17.0, seed=3):
    """Розвести канали короткими випадковими відбиттями. Дешева «глибина»."""
    x = st(x)
    rng = np.random.default_rng(seed)
    out = x.copy()
    for ch in range(2):
        for _ in range(4):
            d = int(SR * rng.uniform(0.002, ms / 1000))
            g = rng.uniform(0.10, 0.22)
            out[d:, ch] += x[:-d, ch] * g
    return out


# ─────────────────────────── простір ───────────────────────────

def make_ir(decay=2.0, predelay=0.02, damp=4200, diffusion=0.014, seed=7):
    """Синтетична імпульсна характеристика залу, стерео.

    Частотно-залежний спад — саме він відрізняє «зал» від «шумного хвоста»:
    низи тримаються ~вдвічі довше за верхи, як у будь-якому реальному
    приміщенні з м'якими поверхнями.
    """
    rng = np.random.default_rng(seed)
    n = int(SR * decay)
    tt = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        w = rng.standard_normal(n)  # незалежний шум на канал = ширина хвоста
        low = lowpass(w, 600) * np.exp(-2.6 * tt / decay)
        mid = bandpass(w, 600, damp) * np.exp(-4.5 * tt / decay)
        high = highpass(w, damp) * np.exp(-9.0 * tt / decay)
        body = low + mid * 0.8 + high * 0.30
        # наростання щільності: реальний зал не б'є повною енергією в нульовій точці
        ir[:, ch] = body * np.clip(tt / diffusion, 0, 1) ** 1.5

    # ранні відбиття — вони дають масштаб приміщення
    for _ in range(14):
        d = int(SR * rng.uniform(0.006, 0.055))
        ch = rng.integers(0, 2)
        ir[d, ch] += rng.uniform(0.25, 0.75) * rng.choice([-1, 1])

    p = int(SR * predelay)
    if p:
        ir = np.vstack([np.zeros((p, 2)), ir])
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-12)  # нормалізація енергії -> wet передбачуваний


def conv(x, ir):
    x, out = st(x), []
    for ch in range(2):
        out.append(signal.fftconvolve(x[:, ch], ir[:, ch]))
    return np.column_stack(out)


def reverb(x, ir, wet=0.30, dry=1.0):
    x = st(x)
    w = conv(x, ir)
    w /= np.max(np.abs(w)) + 1e-12
    d = np.vstack([x, np.zeros((len(w) - len(x), 2))])
    return d * dry + w * wet


def pitch(x, ratio):
    """Vari-speed зсув: 2.0 = октава вгору (і вдвічі коротше).

    Для шимера скорочення не проблема — наступний реверб усе одно
    розтягне матеріал назад.
    """
    fr = Fraction(1 / ratio).limit_denominator(64)
    return signal.resample_poly(x, fr.numerator, fr.denominator, axis=0)


def shimmer(x, ir, wet=0.22, up=2.0, seed=11):
    """Хвіст, транспонований на октаву вгору і відправлений у зал ще раз.

    Це той самий трюк, на якому тримається половина кінематографічних
    інтерфейсів: звук не просто згасає, він «розквітає» вгору.
    """
    x = st(x)
    tail = conv(x, ir)
    hi = pitch(mono(tail), up)
    hi = highpass(hi, 700)
    bloom = conv(hi, ir)
    bloom = np.vstack([bloom, np.zeros((max(0, len(tail) - len(bloom)), 2))])[:len(tail)]
    bloom /= np.max(np.abs(bloom)) + 1e-12
    dry = np.vstack([x, np.zeros((len(tail) - len(x), 2))])
    tail /= np.max(np.abs(tail)) + 1e-12
    return dry + tail * wet * 0.7 + bloom * wet


def creverb(x, ir, wet=0.30):
    """Циркулярний реверб для петель: хвіст загортається на початок.

    Звичайна згортка подовжила б петлю на хвіст і зламала стик.
    Множення спектрів = циклічна згортка, довжина не змінюється.
    """
    x = st(x)
    n = len(x)
    irp = np.zeros((n, 2))
    m = min(len(ir), n)
    irp[:m] = ir[:m]
    w = np.fft.irfft(np.fft.rfft(x, axis=0) * np.fft.rfft(irp, axis=0), n, axis=0)
    w /= np.max(np.abs(w)) + 1e-12
    return x + w * wet


# ─────────────────────────── насичення ───────────────────────────

def saturate(x, drive=1.6):
    """М'який клип. Склеює шари і додає гармонік — на ТВ-динаміку це гучніше
    при тому самому піку."""
    return np.tanh(x * drive) / np.tanh(drive)


def exciter(x, low=40, high=120, amount=0.5):
    """Генератор гармонік для сабу.

    Динаміки телевізора нижче ~120 Гц не грають нічого. Але вухо добудовує
    основний тон за гармоніками — тому саб «чути» навіть там, де його немає.
    Без цього play/logo на вбудованих динаміках просто зникають.
    """
    sub = bandpass(x, low, high, 2)
    h = bandpass(saturate(sub * 3.0, 3.0), high, high * 6, 2)
    return x + h * amount


# ─────────────────────────── збірка ───────────────────────────

def pad(x, dur):
    n = int(SR * dur)
    if np.ndim(x) == 2:
        return np.vstack([x, np.zeros((max(0, n - len(x)), 2))])[:n]
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*layers):
    layers = [np.asarray(l) for l in layers]
    stereo = any(l.ndim == 2 for l in layers)
    n = max(len(l) for l in layers)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    for l in layers:
        if stereo:
            l = st(l)
        out[:len(l)] += l
    return out


def at(x, offset, dur):
    """Покласти шар з зсувом у часі."""
    d = int(SR * offset)
    z = np.zeros((d, 2)) if np.ndim(x) == 2 else np.zeros(d)
    return pad(np.vstack([z, st(x)]) if np.ndim(x) == 2 else np.concatenate([z, x]), dur)


def loopify(x, dur):
    """Загорнути «хвіст поза петлею» назад на початок.

    Для разових подій усередині беду (дзвіночок на 25-й секунді): його реверб
    виходить за межу петлі — і має продовжитись на початку наступного проходу.
    """
    n = int(SR * dur)
    head = pad(x, dur).copy()
    over = x[n:]
    if len(over):
        m = min(len(over), n)
        head[:m] += over[:m]
    return head


# ─────────────────────────── фініш ───────────────────────────

def norm_peak(x, db=-6.0):
    m = np.max(np.abs(x))
    return x / m * 10 ** (db / 20) if m > 0 else x


# Коефіцієнти K-зважування з ITU-R BS.1770 — рахований варіант саме для 48 кГц
_K1 = (np.array([1.53512485958697, -2.69169618940638, 1.19839281085285]),
       np.array([1.0, -1.69065929318241, 0.73248077421585]))
_K2 = (np.array([1.0, -2.0, 1.0]),
       np.array([1.0, -1.99004745483398, 0.99007225036621]))


def lufs(x):
    """Інтегральна гучність за BS.1770.

    Для беду це єдина чесна міра рівня. Повносмуговий RMS міряв би переважно
    саб — і петля з великим низом виходила б «гучною» за цифрою, тихо
    зникаючи на реальному телевізорі. K-зважування ріже низ так само, як його
    ріже вухо, тому нормалізація по LUFS вирівнює саме те, що чути.
    """
    y = st(np.asarray(x, dtype=np.float64))
    for b, a in (_K1, _K2):
        y = signal.lfilter(b, a, y, axis=0)
    return -0.691 + 10 * np.log10(np.sum(np.mean(y ** 2, axis=0)) + 1e-30)


def norm_lufs(x, target=-34.0, ceiling_db=-6.0):
    """Гучність по LUFS + стеля по піку.

    Стеля потрібна, бо бед грає не сам: зверху на нього лягає UI, і сума
    не має впиратись у 0 dBFS.
    """
    x = np.asarray(x, dtype=np.float64)
    y = x * 10 ** ((target - lufs(x)) / 20)
    p, c = np.max(np.abs(y)), 10 ** (ceiling_db / 20)
    return y * (c / p) if p > c else y


def finish(x, peak_db=-6.0, fade_ms=4.0, fade_in_ms=0.25, hp=60.0, lp=None, drive=None):
    """Фейди -> обробка -> нормалізація. Порядок принциповий.

    Фейд на вході має бути на порядок коротшим за вихідний: атака тіку — це
    0.3 мс, і 3-мілісекундний фейд просто зрізав би сам транзієнт разом із
    піком. На вході достатньо прибрати стрибок з нуля, на виході — хвіст.

    hp — параметр, а не константа: крихітному тіку саб не потрібен зовсім
    (hp=250), а logo/play без 30 Гц втрачають половину сенсу.
    """
    x = np.asarray(x, dtype=np.float64)
    x -= np.mean(x, axis=0)          # прибрати DC
    x = highpass(x, hp, 2)
    if lp:
        x = lowpass(x, lp, 2)
    if drive:
        x = saturate(x, drive)
    for ms, sl in ((fade_in_ms, "in"), (fade_ms, "out")):
        f = max(1, int(SR * ms / 1000))
        if len(x) <= 2 * f:
            continue
        ramp = np.linspace(0, 1, f)
        ramp = ramp[:, None] if x.ndim == 2 else ramp
        if sl == "in":
            x[:f] *= ramp
        else:
            x[-f:] *= ramp[::-1]
    return norm_peak(x, peak_db)


def finish_loop(x, loud=-34.0, hp=28.0, ceiling_db=-6.0):
    """Для петель — жодних фейдів на краях, вони б і були тим самим стиком.
    І фільтрація через pfilt, інакше перехідний процес зіпсує початок."""
    x = np.asarray(x, dtype=np.float64)
    x -= np.mean(x, axis=0)
    x = pfilt(x, lambda s: highpass(s, hp, 2))
    return norm_lufs(x, loud, ceiling_db)


def trim(x, thresh_db=-64.0):
    """Обрізати тишу в хвості — важливо для латентності й розміру."""
    thr = 10 ** (thresh_db / 20)
    a = np.max(np.abs(x), axis=1) if np.ndim(x) == 2 else np.abs(x)
    nz = np.where(a > thr)[0]
    return x[: nz[-1] + 1] if len(nz) else x
