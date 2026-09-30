"""
Чистая логика нарезки спрайт-листов — без интерфейса, чтобы её можно было
протестировать напрямую (см. self_test.py) и переиспользовать вне GUI.

Пайплайн для одного кадра:
    1. sample_bg_color   — определить цвет фона (обычно угол листа)
    2. detect_grid_axis  — найти границы строк/колонок по "швам" фона
    3. crop_percent      — (опционально) вручную отсечь долю ячейки (например, убрать скелета)
    4. chroma_key        — сделать фон прозрачным, с плавным затуханием на границе
    5. trim_to_content   — обрезать по границе непрозрачного содержимого
"""

from __future__ import annotations

from dataclasses import dataclass, field
from PIL import Image
import numpy as np


def sample_bg_color(img: Image.Image, x: int = 2, y: int = 2) -> tuple[int, int, int]:
    """Цвет фона, взятый из указанного пикселя (по умолчанию — угол листа)."""
    rgb = img.convert("RGB")
    x = max(0, min(x, rgb.width - 1))
    y = max(0, min(y, rgb.height - 1))
    return rgb.getpixel((x, y))


@dataclass
class GridDetection:
    axis_len: int
    bg: tuple[int, int, int]
    threshold: float
    min_gap: int
    gap_runs: list[tuple[int, int]] = field(default_factory=list)
    boundaries: list[int] = field(default_factory=list)  # позиции разделителей между кадрами
    cell_count: int = 0


def _bg_fraction_per_line(arr: np.ndarray, bg: np.ndarray, axis: str, tol: int) -> np.ndarray:
    """Для axis='col' — доля фона в каждом столбце; для axis='row' — в каждой строке."""
    diff = np.abs(arr.astype(int) - bg)
    within = np.all(diff < tol, axis=-1)  # (H, W) bool
    if axis == "col":
        return within.mean(axis=0)  # по столбцам -> (W,)
    return within.mean(axis=1)  # по строкам -> (H,)


def _runs_from_mask(mask: np.ndarray, min_gap: int) -> list[tuple[int, int]]:
    runs = []
    start = None
    n = len(mask)
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start >= min_gap:
                runs.append((start, i - 1))
            start = None
    if start is not None and n - start >= min_gap:
        runs.append((start, n - 1))
    return runs


def detect_grid_axis(
    img: Image.Image,
    bg: tuple[int, int, int],
    axis: str,
    threshold: float = 0.97,
    min_gap: int = 6,
    color_tol: int = 12,
) -> GridDetection:
    """
    Находит "швы" (полосы фона на всю ширину/высоту) по одной оси.
    axis: "col" — ищем вертикальные швы (разделители колонок),
          "row" — ищем горизонтальные швы (разделители строк).
    """
    arr = np.array(img.convert("RGB"))
    bg_arr = np.array(bg)
    frac = _bg_fraction_per_line(arr, bg_arr, axis, color_tol)
    mask = frac > threshold
    axis_len = len(mask)
    gap_runs = _runs_from_mask(mask, min_gap)

    # Швы, прилегающие к самому краю листа (s==0 или e==axis_len-1), — это ПОЛЯ, а не
    # разделители между кадрами: они лишь подрезают содержимое с краю. Разделителями
    # считаются только швы, лежащие строго между содержимым по обе стороны — иначе край
    # засчитывается как ещё один разделитель и счётчик кадров уезжает на +1 (или +2,
    # если поля есть с обеих сторон).
    content_start, content_end = 0, axis_len
    internal_gaps: list[tuple[int, int]] = []
    for s, e in gap_runs:
        if s <= 0:
            content_start = max(content_start, e + 1)
        elif e >= axis_len - 1:
            content_end = min(content_end, s)
        else:
            internal_gaps.append((s, e))

    boundaries = [content_start]
    for s, e in internal_gaps:
        boundaries.append((s + e) // 2)
    boundaries.append(content_end)
    boundaries = sorted(set(boundaries))
    cell_count = max(0, len(boundaries) - 1)

    return GridDetection(
        axis_len=axis_len,
        bg=bg,
        threshold=threshold,
        min_gap=min_gap,
        gap_runs=gap_runs,
        boundaries=boundaries,
        cell_count=cell_count,
    )


def uniform_boundaries(axis_len: int, count: int) -> list[int]:
    """Равномерная сетка на count ячеек — запасной вариант, когда авто-детект не нужен/не сработал."""
    if count <= 0:
        return [0, axis_len]
    step = axis_len / count
    return [round(i * step) for i in range(count + 1)]


def crop_percent(img: Image.Image, left: float = 0.0, right: float = 0.0, top: float = 0.0, bottom: float = 0.0) -> Image.Image:
    """Отсекает доли ячейки в процентах (0-100) с каждой стороны — например, чтобы убрать
    соседнего персонажа (скелета), когда между ним и нужным спрайтом нет чистого шва фона."""
    w, h = img.size
    x0 = int(w * (left / 100.0))
    x1 = int(w * (1.0 - right / 100.0))
    y0 = int(h * (top / 100.0))
    y1 = int(h * (1.0 - bottom / 100.0))
    x1 = max(x0 + 1, x1)
    y1 = max(y0 + 1, y1)
    return img.crop((x0, y0, x1, y1))


def chroma_key(img: Image.Image, bg: tuple[int, int, int], tol: float = 24.0, edge_tol: float = 48.0) -> Image.Image:
    """Убирает фон: пиксели ближе tol к фону становятся прозрачными, полоса между tol и
    edge_tol плавно затухает (чтобы не было цветной окантовки на границе персонажа)."""
    rgba = np.array(img.convert("RGBA")).astype(float)
    bg_arr = np.array(bg, dtype=float)
    dist = np.linalg.norm(rgba[..., :3] - bg_arr, axis=-1)

    alpha = rgba[..., 3].copy()
    alpha = np.where(dist < tol, 0.0, alpha)
    fade_zone = (dist >= tol) & (dist < edge_tol)
    fade = np.clip((dist - tol) / max(1e-6, (edge_tol - tol)), 0.0, 1.0)
    alpha = np.where(fade_zone, alpha * fade, alpha)

    out = rgba.copy()
    out[..., 3] = alpha
    return Image.fromarray(out.astype(np.uint8), mode="RGBA")


def trim_to_content(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def remove_small_specks(img: Image.Image, min_area_fraction: float = 0.02) -> Image.Image:
    """Убирает мелкие изолированные непрозрачные пятна — декоративные блёстки/пыль/частицы
    фона листа, которые хромакей не поймал (их цвет слишком отличается от цвета фона, чтобы
    попасть под допуск, но сами по себе они не связаны с силуэтом персонажа).

    Оставляет только САМУЮ КРУПНУЮ связную непрозрачную область — считаем её персонажем —
    и обнуляет альфу всех остальных. min_area_fraction — порог (доля от площади самой
    крупной области), ниже которого область считается мусором и всегда убирается, даже если
    почему-то не осталась ровно одна крупная область."""
    from scipy.ndimage import label

    alpha = np.array(img.convert("RGBA"))[..., 3]
    mask = alpha > 10
    if not mask.any():
        return img

    labeled, num = label(mask)
    if num <= 1:
        return img

    sizes = np.bincount(labeled.ravel())
    sizes[0] = 0  # фон (label 0) не считаем
    largest_label = int(np.argmax(sizes))
    largest_size = sizes[largest_label]

    keep = np.zeros_like(mask)
    for lbl in range(1, len(sizes)):
        if sizes[lbl] == 0:
            continue
        if lbl == largest_label or sizes[lbl] >= largest_size * min_area_fraction * 10:
            # доп. условие на случай двух сопоставимых по размеру частей (напр. персонаж
            # случайно распался на 2 области из-за тонкого перешейка) — оставляем и их
            keep |= labeled == lbl

    out = np.array(img.convert("RGBA"))
    out[~keep, 3] = 0
    return Image.fromarray(out, mode="RGBA")


def process_cell(
    sheet: Image.Image,
    cell_box: tuple[int, int, int, int],
    bg: tuple[int, int, int],
    tol: float,
    edge_tol: float,
    crop: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0),
    clean_specks: bool = False,
) -> Image.Image:
    """Полный пайплайн для одной ячейки: вырезать -> ручная обрезка -> хромакей ->
    (опционально) убрать мелкий мусор (блёстки/пыль) -> обрезка по содержимому.

    clean_specks по умолчанию ВЫКЛЮЧЕН: он опасен для персонажей, у которых легитимная
    деталь (щит, оружие на отлёте) держится на тонкой полупрозрачной перемычке — на
    другом листе именно так случайно срезало щит воина. Включай только когда точно
    видел на превью лишнюю блёстку/пыль и проверил, что реальные детали не пострадали."""
    cell = sheet.crop(cell_box).convert("RGBA")
    left, right, top, bottom = crop
    if any((left, right, top, bottom)):
        cell = crop_percent(cell, left, right, top, bottom)
    keyed = chroma_key(cell, bg, tol, edge_tol)
    if clean_specks:
        keyed = remove_small_specks(keyed)
    return trim_to_content(keyed)


def build_export_filename(unit: str, action: str, variant_index: int, total: int) -> str:
    """Имя экспортируемого файла по схеме {тип_юнита}_{действие}_{вариант}.png — это и есть
    контракт между инструментом и игрой: код в игре ищет файл по job_id + текущему действию,
    без необходимости прописывать каждый юнит вручную. При total<=1 суффикс варианта не нужен."""
    unit_slug = (unit or "unit").strip().lower().replace(" ", "_") or "unit"
    action_slug = (action or "frame").strip().lower().replace(" ", "_") or "frame"
    if total <= 1:
        return f"{unit_slug}_{action_slug}.png"
    letter = chr(ord("a") + variant_index) if variant_index < 26 else str(variant_index + 1)
    return f"{unit_slug}_{action_slug}_{letter}.png"


def resize_to_height(img: Image.Image, target_h: float) -> Image.Image:
    w, h = img.size
    if h <= 0:
        return img
    scale = target_h / h
    new_w = max(1, round(w * scale))
    new_h = max(1, round(target_h))
    return img.resize((new_w, new_h), Image.LANCZOS)
