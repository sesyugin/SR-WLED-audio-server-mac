#!/usr/bin/env python3
"""Рисует схемы для README.

Схемы рисуются кодом по той же причине, что и знак программы: нарисованная
руками картинка расходится с кодом молча. Таблица полос читается прямо из
Bucketizer.swift — если её однажды тронут, схема поедет вместе с ней.

    python3 scripts/make-diagrams.py

Кладёт docs/diagram-*.svg. Фон у схем свой, тёмный: README читают и в светлой
теме, и в тёмной, а так картинка выглядит одинаково в обеих.
"""
import io
import os
import re
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs")

INK = "#13100E"      # фон карточки — тот же тон, что у сцены
PANEL = "#1D1917"    # блок внутри карточки
AMBER = "#E8862A"    # акцент
AMBER_DIM = "#8A5620"
TEXT = "#F0EBE6"
MUTED = "#9A8F86"
LINE = "#3A322D"
FONT = ("-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', "
        "Arial, sans-serif")


def band_edges():
    """Границы полос из прошивки, прочитанные из исходника."""
    path = os.path.join(ROOT, "Sources/SRWLEDCore/DSP/Bucketizer.swift")
    source = io.open(path, encoding="utf-8").read()
    block = source.split("wledBandEdges: [Float] = [")[1].split("]")[0]
    edges = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", block)]
    if len(edges) != 17:
        raise SystemExit("ожидалось 17 границ, найдено %d" % len(edges))
    return edges


def text(x, y, s, size=13, fill=TEXT, weight="400", anchor="start", mono=False):
    family = "ui-monospace, SFMono-Regular, Menlo, monospace" if mono else FONT
    return ('<text x="%.1f" y="%.1f" font-family="%s" font-size="%s" '
            'font-weight="%s" fill="%s" text-anchor="%s">%s</text>'
            % (x, y, family, size, weight, fill, anchor, s))


def card(width, height):
    return ('<rect x="0" y="0" width="%d" height="%d" rx="14" fill="%s"/>'
            % (width, height, INK))


def svg(width, height, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
            'viewBox="0 0 %d %d" role="img">%s</svg>'
            % (width, height, width, height, "".join(body)))


# ─────────────────────────────────────────────────────────── путь сигнала

def diagram_chain():
    W, H = 1240, 300
    parts = [card(W, H)]
    parts.append(text(36, 46, "Путь сигнала", 17, TEXT, "600"))
    parts.append(text(36, 70, "от того, что играет, до светящейся полосы на ленте",
                      13, MUTED))

    stages = [
        ("Системный звук", "CoreAudio\nprocess tap", "драйвер не нужен,\nзвук идёт в колонки"),
        ("Окно анализа", "2048 отсчётов,\nшаг 512", "новый кадр\nкаждые 10.7 мс"),
        ("БПФ", "окно Hann,\nсвёртка по энергии", "1024 бина\nв 16 полос"),
        ("Полосы", "таблица\nиз прошивки", "43 Гц … 9259 Гц"),
        ("Пакет", "44 байта,\naudiosync v2", "не чаще\n50 в секунду"),
        ("Лента", "WLED\nAudio Reactive", "режим Receive,\nпорт 11988"),
    ]

    box_w, box_h, gap = 172, 116, 30
    x0 = 36
    y0 = 104
    for i, (title, mid, note) in enumerate(stages):
        x = x0 + i * (box_w + gap)
        last = i == len(stages) - 1
        fill = PANEL if not last else "#241B12"
        stroke = LINE if not last else AMBER_DIM
        parts.append('<rect x="%.1f" y="%d" width="%d" height="%d" rx="10" '
                     'fill="%s" stroke="%s" stroke-width="1"/>'
                     % (x, y0, box_w, box_h, fill, stroke))
        parts.append(text(x + box_w / 2, y0 + 27, title, 13,
                          AMBER if last else TEXT, "600", "middle"))
        for j, line in enumerate(mid.split("\n")):
            parts.append(text(x + box_w / 2, y0 + 52 + j * 16, line, 12, MUTED,
                              "400", "middle", mono=True))
        for j, line in enumerate(note.split("\n")):
            parts.append(text(x + box_w / 2, y0 + 92 + j * 14, line, 11, MUTED,
                              "400", "middle"))
        if not last:
            ax = x + box_w + 6
            ay = y0 + box_h / 2
            parts.append('<path d="M%.1f %.1f H%.1f" stroke="%s" stroke-width="1.5"/>'
                         % (ax, ay, ax + gap - 14, ay, ))
            parts.append('<path d="M%.1f %.1f l-6 -4 v8 z" fill="%s"/>'
                         % (ax + gap - 12, ay, AMBER))

    # Итоговая строка: что именно уходит в сеть.
    y = y0 + box_h + 44
    parts.append('<line x1="36" y1="%d" x2="%d" y2="%d" stroke="%s"/>'
                 % (y - 20, W - 36, y - 20, LINE))
    parts.append(text(36, y, "В сеть уходит только это:", 12, MUTED))
    parts.append(text(215, y, "16 значений эквалайзера и несколько чисел уровня. "
                              "Звук не записывается и не передаётся — "
                              "восстановить его по 44 байтам нельзя.",
                      12, TEXT))
    return svg(W, H, parts)


# ─────────────────────────────────────────────────────────── таблица полос

def diagram_bands():
    edges = band_edges()
    bin_hz = 48000.0 / 2048.0          # шаг БПФ при 48 кГц и окне 2048
    naive = [40 * (10000.0 / 40.0) ** (i / 16.0) for i in range(17)]

    W, H = 1240, 430
    parts = [card(W, H)]
    parts.append(text(36, 46, "Почему полосы взяты из прошивки, а не из логарифма",
                      17, TEXT, "600"))
    parts.append(text(36, 70,
                      "Эффекты WLED рисовались под эту таблицу: каждый канал светит "
                      "своим цветом в своей точке ленты", 13, MUTED))

    left, right = 60, W - 84
    lo, hi = 30.0, 12000.0

    def px(f):
        return left + (right - left) * (math.log10(f) - math.log10(lo)) / (
            math.log10(hi) - math.log10(lo))

    row1, row2, row3 = 122, 214, 318
    axis_y = H - 46

    # Общая сетка: обе раскладки читаются по одной и той же шкале.
    for f in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        x = px(f)
        parts.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" '
                     'stroke-width="1" opacity="0.55"/>' % (x, row1 - 6, x, axis_y, LINE))
        label = "%g к" % (f / 1000.0) if f >= 1000 else "%d" % f
        parts.append(text(x, axis_y + 20, label, 11, MUTED, "400", "middle"))
    parts.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>'
                 % (left, axis_y, right, axis_y, LINE))
    parts.append(text(right + 10, axis_y + 20, "Гц", 11, MUTED))

    # Ряд 1 — таблица прошивки.
    parts.append(text(36, row1 - 14, "Таблица прошивки — 16 полос, 43 … 9259 Гц",
                      12, AMBER, "600"))
    for i in range(16):
        a, b = px(edges[i]), px(edges[i + 1])
        parts.append('<rect x="%.1f" y="%d" width="%.1f" height="36" rx="3" '
                     'fill="%s" opacity="%.2f"/>'
                     % (a + 1, row1, max(2.0, b - a - 2), AMBER, 0.42 + 0.035 * i))
        if b - a > 24:
            parts.append(text((a + b) / 2, row1 + 23, str(i + 1), 11, INK,
                              "700", "middle"))

    # Ряд 2 — наивная логарифмическая сетка. Три нижние полосы выделены.
    parts.append(text(36, row2 - 14, "Логарифмическая сетка 40 … 10000 Гц",
                      12, MUTED, "600"))
    for i in range(16):
        a, b = px(naive[i]), px(naive[i + 1])
        narrow = (naive[i + 1] - naive[i]) < bin_hz * 1.5
        parts.append('<rect x="%.1f" y="%d" width="%.1f" height="36" rx="3" '
                     'fill="%s" fill-opacity="%s" stroke="%s" stroke-width="1"/>'
                     % (a + 1, row2, max(2.0, b - a - 2),
                        "#C4453A" if narrow else "none",
                        "0.45" if narrow else "0", "#C4453A" if narrow else LINE))

    # Ряд 3 — сами бины БПФ. Они равномерны по частоте, а шкала логарифмическая,
    # поэтому слева их единицы, справа сотни: это и есть вся суть.
    parts.append(text(36, row3 - 14,
                      "Бины БПФ — по %.1f Гц каждый, равномерно по частоте" % bin_hz,
                      12, MUTED, "600"))
    k = 1
    while k * bin_hz < hi:
        f = k * bin_hz
        if f >= lo:
            x = px(f)
            parts.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" '
                         'stroke-width="1" opacity="0.55"/>' % (x, row3, x, row3 + 24, "#6FA8C4"))
        k += 1

    # Подпись к выделенным полосам — с настоящими числами.
    widths = ", ".join("%.0f" % (naive[i + 1] - naive[i]) for i in range(3))
    bracket_a, bracket_b = px(naive[0]), px(naive[3])
    by = row2 + 48
    parts.append('<path d="M%.1f %d v8 H%.1f v-8" stroke="%s" fill="none" '
                 'stroke-width="1.5"/>' % (bracket_a, by, bracket_b, "#C4453A"))
    parts.append(text(bracket_b + 12, by + 12,
                      "первые три полосы шириной %s Гц — это один бин на полосу; "
                      "бас там достраивался интерполяцией соседей" % widths,
                      12, TEXT))
    return svg(W, H, parts)


# ─────────────────────────────────────────────────────────── пакет

def diagram_packet():
    W, H = 1240, 330
    parts = [card(W, H)]
    parts.append(text(36, 46, "Что уходит в сеть: 44 байта", 17, TEXT, "600"))
    parts.append(text(36, 70,
                      "Формат задан прошивкой: размер и заголовок она проверяет, "
                      "и только тогда отвечает «v2»", 13, MUTED))

    fields = [
        (0, 6, "заголовок", "00002\\0", AMBER),
        (6, 2, "давление", "8.8", "#7E6BA8"),
        (8, 4, "sampleRaw", "float", "#4E8FA8"),
        (12, 4, "sampleSmth", "float", "#4E8FA8"),
        (16, 1, "пик", "0/1", "#C4453A"),
        (17, 1, "счётчик", "кадра", "#C4453A"),
        (18, 16, "16 полос эквалайзера", "по байту на полосу", AMBER),
        (34, 2, "нули", "переходы", "#7E6BA8"),
        (36, 4, "магнитуда", "float", "#4E8FA8"),
        (40, 4, "главный пик", "Гц", "#4E8FA8"),
    ]

    left, right = 40, W - 40
    unit = (right - left) / 44.0
    y = 118
    height = 54
    for offset, size, name, note, colour in fields:
        x = left + offset * unit
        w = size * unit
        parts.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" rx="5" '
                     'fill="%s" opacity="0.30" stroke="%s" stroke-width="1"/>'
                     % (x + 1, y, w - 2, height, colour, colour))
        cx = x + w / 2
        if w > 74:
            parts.append(text(cx, y + 23, name, 12, TEXT, "600", "middle"))
            parts.append(text(cx, y + 40, note, 11, MUTED, "400", "middle"))
        elif w > 34:
            parts.append(text(cx, y + 31, name, 11, TEXT, "600", "middle"))
        else:
            # Однобайтовое поле: имя не влезает, поэтому уходит вниз на выноске.
            leg = y + height + 4
            drop = 18 if offset == 16 else 34
            parts.append('<path d="M%.1f %d V%d" stroke="%s" stroke-width="1" '
                         'opacity="0.7"/>' % (cx, leg, leg + drop, colour))
            parts.append(text(cx + 6, leg + drop + 4, "%s — %s" % (name, note),
                              11, MUTED))
        parts.append(text(x + 2, y - 8, str(offset), 10, MUTED, "400", "start",
                          mono=True))

    parts.append(text(left, y + height + 18, "смещение в байтах", 11, MUTED))
    parts.append(text(right, y + height + 18, "44", 11, MUTED, "400", "end",
                      mono=True))

    note_y = y + height + 106
    parts.append('<line x1="40" y1="%d" x2="%d" y2="%d" stroke="%s"/>'
                 % (note_y - 22, W - 40, note_y - 22, LINE))
    parts.append(text(40, note_y,
                      "Счётчик кадра не обнуляется на тишине: прошивка принимает пакет "
                      "только если счётчик вырос — обнулив его, лентой перестают "
                      "управлять после первой же паузы.", 12, TEXT))
    return svg(W, H, parts)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, body in (("chain", diagram_chain()),
                       ("bands", diagram_bands()),
                       ("packet", diagram_packet())):
        path = os.path.join(OUT, "diagram-%s.svg" % name)
        io.open(path, "w", encoding="utf-8").write(body)
        print("нарисовано:", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
