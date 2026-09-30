"""
Sprite Slicer — локальное настольное приложение (Tkinter, без браузера) для нарезки
спрайт-листов на отдельные прозрачные PNG-кадры.

Возможности:
  - Открыть PNG/WEBP спрайт-лист.
  - Взять цвет фона пипеткой (клик по картинке) или вручную по RGB.
  - Авто-детект сетки строк/колонок по швам фона — с ползунком чувствительности.
  - Ручная правка числа строк/колонок, если авто-детект ошибся (как это было с
    листом воина: авто по ширине давало 13 колонок, а на самом деле их 14).
  - Ручная обрезка кадра по краям в процентах — чтобы убрать лишнего персонажа
    (например, скелета) там, где между ним и нужным спрайтом нет чистого шва фона.
  - Клик по кадру в сетке — включить/выключить его для экспорта.
  - Предпросмотр выбранного кадра "было / стало" плюс в реальном игровом масштабе.
  - Экспорт выбранных кадров как отдельные прозрачные PNG в указанную папку.

Запуск: python sprite_slicer_app.py
"""

from __future__ import annotations

import os
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, colorchooser

from PIL import Image, ImageTk

import slicer_core as sc

MAX_CANVAS_W = 900
MAX_CANVAS_H = 560


class SpriteSlicerApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Sprite Slicer — нарезка спрайт-листов")
        self.root.geometry("1360x920")

        # --- состояние ---
        self.sheet: Image.Image | None = None
        self.sheet_path: str = ""
        self.bg_color: tuple[int, int, int] = (255, 255, 255)
        self.cols_boundaries: list[int] = []
        self.rows_boundaries: list[int] = []
        self.display_scale: float = 1.0
        self.pick_bg_mode = tk.BooleanVar(value=False)
        self.selected_cells: dict[tuple[int, int], bool] = {}  # dict = сохраняет порядок клика (для анимации/имени файла)
        self.preview_cell: tuple[int, int] | None = None
        self.canvas_img_ref = None  # держим ссылку, чтобы Tk не собрал картинку в GC
        self.preview_img_refs: list = []
        self.play_img_refs: list = []  # отдельно от preview_img_refs, чтобы плеер и превью не затирали ссылки друг друга
        self.play_job_id: str | None = None
        self.play_index: int = 0
        self.is_playing: bool = False

        # --- рабочая область (для огромных атласов из нескольких секций/анимаций
        # с разным фоном — детект сетки и разметка работают только внутри неё) ---
        self.region_select_mode = tk.BooleanVar(value=False)
        self.work_region: tuple[int, int, int, int] | None = None  # (x0,y0,x1,y1) в координатах листа
        self._press_pos: tuple[int, int] | None = None
        self._drag_rect_id: int | None = None

        # --- блоки анимаций: произвольный прямоугольник клеток сетки = 1 анимация,
        # у каждого блока свой цвет фона (разные секции листа часто на разном фоне) ---
        self.block_select_mode = tk.BooleanVar(value=False)
        self.anim_blocks: dict[int, dict] = {}
        self.block_thumb_refs: list = []
        self._next_block_id: int = 0
        self._bg_pick_target_block: int | None = None

        self._build_ui()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        root = self.root
        root.columnconfigure(0, weight=3)
        root.columnconfigure(1, weight=2)
        root.rowconfigure(0, weight=1)

        # ---- левая часть: холст с листом ----
        left = ttk.Frame(root, padding=8)
        left.grid(row=0, column=0, sticky="nsew")
        left.rowconfigure(2, weight=1)
        left.columnconfigure(0, weight=1)

        toolbar = ttk.Frame(left)
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 4))
        ttk.Button(toolbar, text="Открыть спрайт-лист…", command=self.on_open).pack(side="left")
        ttk.Checkbutton(toolbar, text="Пипетка фона (клик по картинке)", variable=self.pick_bg_mode).pack(side="left", padx=12)
        self.bg_swatch = tk.Canvas(toolbar, width=22, height=22, highlightthickness=1, highlightbackground="#888")
        self.bg_swatch.pack(side="left", padx=(0, 4))
        ttk.Button(toolbar, text="Цвет фона вручную…", command=self.on_pick_bg_manual).pack(side="left")
        self.status_label = ttk.Label(toolbar, text="Файл не загружен", foreground="#888")
        self.status_label.pack(side="left", padx=16)

        region_bar = ttk.Frame(left)
        region_bar.grid(row=1, column=0, sticky="ew", pady=(0, 6))
        ttk.Checkbutton(
            region_bar, text="Выделить рабочую область (тяни мышкой по листу)",
            variable=self.region_select_mode,
        ).pack(side="left")
        ttk.Button(region_bar, text="Сбросить область (весь лист)", command=self.on_reset_region).pack(side="left", padx=(10, 0))
        self.region_label = ttk.Label(region_bar, text="Область: весь лист", foreground="#888")
        self.region_label.pack(side="left", padx=12)

        self.canvas = tk.Canvas(left, background="#2b2b2b", highlightthickness=1, highlightbackground="#555")
        self.canvas.grid(row=2, column=0, sticky="nsew")
        self.canvas.bind("<ButtonPress-1>", self._on_canvas_press)
        self.canvas.bind("<B1-Motion>", self._on_canvas_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_canvas_release)

        legend = ttk.Label(
            left,
            text="Синяя рамка — рабочая область. Зелёная — кадр выбран для экспорта. Клик по кадру — включить/выключить.",
            foreground="#888",
        )
        legend.grid(row=3, column=0, sticky="w", pady=(6, 0))

        # ---- правая часть: параметры (в прокручиваемом контейнере — панель уже не помещается
        # на невысоком экране после добавления таблицы разметки по рядам) ----
        right_container = ttk.Frame(root)
        right_container.grid(row=0, column=1, sticky="nsew")
        right_container.rowconfigure(0, weight=1)
        right_container.columnconfigure(0, weight=1)

        right_canvas = tk.Canvas(right_container, highlightthickness=0)
        right_scroll = ttk.Scrollbar(right_container, orient="vertical", command=right_canvas.yview)
        right_canvas.configure(yscrollcommand=right_scroll.set)
        right_canvas.grid(row=0, column=0, sticky="nsew")
        right_scroll.grid(row=0, column=1, sticky="ns")

        right = ttk.Frame(right_canvas, padding=8)
        right_window = right_canvas.create_window((0, 0), window=right, anchor="nw")
        right.bind("<Configure>", lambda e: right_canvas.configure(scrollregion=right_canvas.bbox("all")))
        right_canvas.bind("<Configure>", lambda e: right_canvas.itemconfig(right_window, width=e.width))

        def _on_right_mousewheel(event):
            right_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        right_canvas.bind_all("<MouseWheel>", _on_right_mousewheel)

        right.columnconfigure(0, weight=1)

        grid_box = ttk.LabelFrame(right, text="Сетка кадров", padding=8)
        grid_box.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        grid_box.columnconfigure(1, weight=1)

        ttk.Label(grid_box, text="Чувствительность авто-детекта").grid(row=0, column=0, columnspan=2, sticky="w")
        self.detect_threshold = tk.DoubleVar(value=0.97)
        ttk.Scale(grid_box, from_=0.80, to=0.999, variable=self.detect_threshold, orient="horizontal").grid(row=1, column=0, columnspan=2, sticky="ew")

        ttk.Button(grid_box, text="Авто-детект сетки", command=self.on_auto_detect).grid(row=2, column=0, columnspan=2, sticky="ew", pady=(6, 10))

        ttk.Label(grid_box, text="Колонок:").grid(row=3, column=0, sticky="w")
        self.cols_var = tk.IntVar(value=0)
        cols_spin = ttk.Spinbox(grid_box, from_=1, to=60, textvariable=self.cols_var, width=6, command=self.on_manual_grid_change)
        cols_spin.grid(row=3, column=1, sticky="w")
        cols_spin.bind("<Return>", lambda e: self.on_manual_grid_change())

        ttk.Label(grid_box, text="Строк:").grid(row=4, column=0, sticky="w")
        self.rows_var = tk.IntVar(value=0)
        rows_spin = ttk.Spinbox(grid_box, from_=1, to=60, textvariable=self.rows_var, width=6, command=self.on_manual_grid_change)
        rows_spin.grid(row=4, column=1, sticky="w")
        rows_spin.bind("<Return>", lambda e: self.on_manual_grid_change())

        ttk.Label(grid_box, text="(если авто ошибается — поправь числа руками и нажми Enter)", foreground="#888", wraplength=280).grid(row=5, column=0, columnspan=2, sticky="w", pady=(4, 0))

        key_box = ttk.LabelFrame(right, text="Удаление фона", padding=8)
        key_box.grid(row=1, column=0, sticky="ew", pady=(0, 8))
        key_box.columnconfigure(0, weight=1)

        ttk.Label(key_box, text="Допуск (порог прозрачности)").grid(row=0, column=0, sticky="w")
        self.tol_var = tk.DoubleVar(value=24.0)
        ttk.Scale(key_box, from_=0, to=120, variable=self.tol_var, orient="horizontal", command=lambda e: self.refresh_preview()).grid(row=1, column=0, sticky="ew")

        ttk.Label(key_box, text="Плавность границы (feather)").grid(row=2, column=0, sticky="w")
        self.edge_tol_var = tk.DoubleVar(value=48.0)
        ttk.Scale(key_box, from_=0, to=150, variable=self.edge_tol_var, orient="horizontal", command=lambda e: self.refresh_preview()).grid(row=3, column=0, sticky="ew")

        crop_box = ttk.LabelFrame(right, text="Ручная обрезка кадра (%) — убрать лишнего персонажа/скелета", padding=8)
        crop_box.grid(row=2, column=0, sticky="ew", pady=(0, 8))
        for i in range(4):
            crop_box.columnconfigure(i, weight=1)

        self.crop_left = tk.DoubleVar(value=0.0)
        self.crop_right = tk.DoubleVar(value=0.0)
        self.crop_top = tk.DoubleVar(value=0.0)
        self.crop_bottom = tk.DoubleVar(value=0.0)
        for label, var, col in [("Слева", self.crop_left, 0), ("Справа", self.crop_right, 1), ("Сверху", self.crop_top, 2), ("Снизу", self.crop_bottom, 3)]:
            f = ttk.Frame(crop_box)
            f.grid(row=0, column=col, sticky="ew", padx=2)
            ttk.Label(f, text=label).pack()
            sb = ttk.Spinbox(f, from_=0, to=90, textvariable=var, width=5, command=self.refresh_preview)
            sb.pack()
            sb.bind("<Return>", lambda e: self.refresh_preview())
        ttk.Label(crop_box, text="Применяется ко ВСЕМ экспортируемым кадрам одинаково.", foreground="#888", wraplength=300).grid(row=1, column=0, columnspan=4, sticky="w", pady=(4, 0))

        sel_box = ttk.LabelFrame(right, text="Выбор кадров", padding=8)
        sel_box.grid(row=3, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(sel_box, text="Выбрать все", command=self.on_select_all).pack(side="left", padx=(0, 6))
        ttk.Button(sel_box, text="Снять выбор", command=self.on_select_none).pack(side="left")
        self.sel_count_label = ttk.Label(sel_box, text="Выбрано: 0")
        self.sel_count_label.pack(side="left", padx=12)

        # --- Проигрыватель: прогоняет выбранные кадры в порядке клика как анимацию ---
        player_box = ttk.LabelFrame(right, text="Проигрыватель (выбранные кадры по порядку клика)", padding=8)
        player_box.grid(row=4, column=0, sticky="ew", pady=(0, 8))

        player_row = ttk.Frame(player_box)
        player_row.pack(fill="x")

        self.play_btn = ttk.Button(player_row, text="▶ Играть", command=self.on_play_toggle)
        self.play_btn.pack(side="left", padx=(0, 10))

        ttk.Label(player_row, text="Кадров/сек:").pack(side="left")
        self.fps_var = tk.IntVar(value=6)
        fps_spin = ttk.Spinbox(player_row, from_=1, to=24, textvariable=self.fps_var, width=4)
        fps_spin.pack(side="left", padx=(4, 10))

        self.play_frame_label = ttk.Label(player_row, text="кадр —/—")
        self.play_frame_label.pack(side="left")

        player_canvas_row = ttk.Frame(player_box)
        player_canvas_row.pack(fill="x", pady=(8, 0))
        ttk.Label(player_canvas_row, text="Истинный размер").pack(side="left", expand=True)
        ttk.Label(player_canvas_row, text="Увеличено ×10").pack(side="left", expand=True)

        player_canvas_imgs = ttk.Frame(player_box)
        player_canvas_imgs.pack(fill="x")
        self.play_true_cv = tk.Canvas(player_canvas_imgs, width=140, height=100, background="#3a3a3a", highlightthickness=0)
        self.play_true_cv.pack(side="left", expand=True)
        self.play_mag_cv = tk.Canvas(player_canvas_imgs, width=140, height=100, background="#3a3a3a", highlightthickness=0)
        self.play_mag_cv.pack(side="left", expand=True)

        ttk.Label(player_box, text="Порядок = порядок клика по кадрам (не обязательно слева направо).", foreground="#888", wraplength=300).pack(fill="x", pady=(4, 0))

        prev_box = ttk.LabelFrame(right, text="Предпросмотр выбранного кадра (клик по кадру слева)", padding=8)
        prev_box.grid(row=5, column=0, sticky="nsew")
        right.rowconfigure(5, weight=1)
        prev_box.columnconfigure(0, weight=1)
        prev_box.columnconfigure(1, weight=1)
        prev_box.columnconfigure(2, weight=1)

        ttk.Label(prev_box, text="Было").grid(row=0, column=0)
        ttk.Label(prev_box, text="Стало (после обработки)").grid(row=0, column=1)
        ttk.Label(prev_box, text="Реальный масштаб игры ×8").grid(row=0, column=2)

        self.preview_before_cv = tk.Canvas(prev_box, width=140, height=140, background="#3a3a3a", highlightthickness=0)
        self.preview_before_cv.grid(row=1, column=0, sticky="n")
        self.preview_after_cv = tk.Canvas(prev_box, width=140, height=140, background="#3a3a3a", highlightthickness=0)
        self.preview_after_cv.grid(row=1, column=1, sticky="n")
        self.preview_scaled_cv = tk.Canvas(prev_box, width=140, height=140, background="#3a3a3a", highlightthickness=0)
        self.preview_scaled_cv.grid(row=1, column=2, sticky="n")

        self.preview_dims_label = ttk.Label(prev_box, text="—")
        self.preview_dims_label.grid(row=2, column=0, columnspan=3, pady=(6, 0))

        export_box = ttk.LabelFrame(right, text="Экспорт — имя файла = тип_юнита + действие + вариант", padding=8)
        export_box.grid(row=6, column=0, sticky="ew", pady=(8, 0))

        name_row = ttk.Frame(export_box)
        name_row.pack(fill="x", pady=(0, 8))

        unit_col = ttk.Frame(name_row)
        unit_col.pack(side="left", expand=True, fill="x", padx=(0, 6))
        ttk.Label(unit_col, text="Тип юнита (job_id)").pack(anchor="w")
        self.unit_type_var = tk.StringVar(value="warrior")
        ttk.Entry(unit_col, textvariable=self.unit_type_var).pack(fill="x")

        action_col = ttk.Frame(name_row)
        action_col.pack(side="left", expand=True, fill="x")
        ttk.Label(action_col, text="Действие").pack(anchor="w")
        self.action_var = tk.StringVar(value="attack")
        action_combo = ttk.Combobox(
            action_col, textvariable=self.action_var,
            values=["idle", "walk", "attack", "block", "death", "carry", "chop", "gather"],
        )
        action_combo.pack(fill="x")

        self.export_preview_label = ttk.Label(export_box, text="Пример: —", foreground="#888")
        self.export_preview_label.pack(fill="x", pady=(0, 8))
        for var in (self.unit_type_var, self.action_var):
            var.trace_add("write", lambda *args: self._update_export_preview())

        ttk.Button(export_box, text="Экспортировать выбранные кадры…", command=self.on_export).pack(fill="x")
        self._update_export_preview()

        # --- Разметка блоками: произвольный прямоугольник клеток на сетке = 1 анимация.
        # НЕ предполагаем "1 ряд = 1 действие" (на практике это не всегда так — действие может
        # занимать часть ряда или несколько рядов), и у КАЖДОГО блока — свой цвет фона (разные
        # секции листа часто залиты разным оттенком под разные анимации/роли). ---
        block_box = ttk.LabelFrame(right, text="Разметка блоками (произвольная область сетки = 1 анимация)", padding=8)
        block_box.grid(row=7, column=0, sticky="ew", pady=(8, 0))

        block_hint = ttk.Label(
            block_box,
            text="Включи «Выделить блок» ниже, протяни мышкой по холсту прямоугольник клеток (может быть "
                 "часть ряда, несколько рядов — что угодно). Блок появится в списке — впиши роль/действие, "
                 "при необходимости возьми фон именно для этого блока (кнопка 🎨).",
            foreground="#888", wraplength=340,
        )
        block_hint.pack(fill="x", pady=(0, 6))

        mode_row = ttk.Frame(block_box)
        mode_row.pack(fill="x", pady=(0, 6))
        ttk.Checkbutton(mode_row, text="Выделить блок (тяни по клеткам)", variable=self.block_select_mode).pack(side="left")

        table_frame = ttk.Frame(block_box)
        table_frame.pack(fill="both", expand=True)

        self.block_table_canvas = tk.Canvas(table_frame, height=230, background="#2b2b2b", highlightthickness=0)
        block_scroll = ttk.Scrollbar(table_frame, orient="vertical", command=self.block_table_canvas.yview)
        self.block_table_canvas.configure(yscrollcommand=block_scroll.set)
        self.block_table_canvas.pack(side="left", fill="both", expand=True)
        block_scroll.pack(side="right", fill="y")

        self.block_table_inner = ttk.Frame(self.block_table_canvas)
        self._block_table_window = self.block_table_canvas.create_window((0, 0), window=self.block_table_inner, anchor="nw")
        self.block_table_inner.bind(
            "<Configure>",
            lambda e: self.block_table_canvas.configure(scrollregion=self.block_table_canvas.bbox("all")),
        )
        self.block_table_canvas.bind(
            "<Configure>",
            lambda e: self.block_table_canvas.itemconfig(self._block_table_window, width=e.width),
        )

        ttk.Button(block_box, text="Экспортировать все блоки…", command=self.on_export_blocks).pack(fill="x", pady=(8, 0))

    def _add_block(self, row_start: int, row_end: int, col_start: int, col_end: int) -> None:
        top_left_box = self._cell_box(row_start, col_start)
        bg = sc.sample_bg_color(self.sheet.crop(top_left_box)) if top_left_box else self.bg_color
        block_id = self._next_block_id
        self._next_block_id += 1
        self.anim_blocks[block_id] = {
            "row_start": row_start, "row_end": row_end, "col_start": col_start, "col_end": col_end,
            "role": tk.StringVar(value=""), "action": tk.StringVar(value=""),
            "bg_color": bg, "crop_right": tk.DoubleVar(value=0.0),
        }
        self._redraw_canvas()
        self._rebuild_block_table()

    def _remove_block(self, block_id: int) -> None:
        self.anim_blocks.pop(block_id, None)
        self._redraw_canvas()
        self._rebuild_block_table()

    def _pick_bg_for_block(self, block_id: int) -> None:
        self._bg_pick_target_block = block_id
        self.pick_bg_mode.set(True)
        self._set_status("Кликни по листу, чтобы взять цвет фона для этого блока")

    def _rebuild_block_table(self) -> None:
        for child in self.block_table_inner.winfo_children():
            child.destroy()
        self.block_thumb_refs.clear()

        headers = ["Диапазон", "Превью", "Фон", "Роль (job_id)", "Действие", "Обрезка справа %", ""]
        for col, text in enumerate(headers):
            ttk.Label(self.block_table_inner, text=text, foreground="#aaa").grid(row=0, column=col, padx=3, pady=(0, 4), sticky="w")

        for i, (block_id, cfg) in enumerate(sorted(self.anim_blocks.items())):
            r0, r1, c0, c1 = cfg["row_start"], cfg["row_end"], cfg["col_start"], cfg["col_end"]
            n_frames = (r1 - r0 + 1) * (c1 - c0 + 1)
            grid_row = i + 1

            range_txt = f"р{r0}" if r0 == r1 else f"р{r0}-{r1}"
            range_txt += f", к{c0}" if c0 == c1 else f", к{c0}-{c1}"
            ttk.Label(self.block_table_inner, text=f"{range_txt} ({n_frames})").grid(row=grid_row, column=0, padx=3, pady=2, sticky="w")

            thumb_lbl = tk.Label(self.block_table_inner, background="#3a3a3a")
            box = self._cell_box(r0, c0)
            if box is not None:
                try:
                    processed = sc.process_cell(self.sheet, box, cfg["bg_color"], tol=self.tol_var.get(), edge_tol=self.edge_tol_var.get())
                    disp = self._fit_for_preview(processed, 34)
                    tkimg = ImageTk.PhotoImage(disp)
                    self.block_thumb_refs.append(tkimg)
                    thumb_lbl.config(image=tkimg)
                except Exception:
                    pass
            thumb_lbl.grid(row=grid_row, column=1, padx=3)

            bg_frame = ttk.Frame(self.block_table_inner)
            bg_frame.grid(row=grid_row, column=2, padx=3)
            bg_swatch = tk.Canvas(bg_frame, width=16, height=16, highlightthickness=1, highlightbackground="#888")
            bg_swatch.create_rectangle(0, 0, 16, 16, fill="#%02x%02x%02x" % cfg["bg_color"], outline="")
            bg_swatch.pack(side="left")
            ttk.Button(bg_frame, text="🎨", width=3, command=lambda bid=block_id: self._pick_bg_for_block(bid)).pack(side="left")

            ttk.Entry(self.block_table_inner, textvariable=cfg["role"], width=10).grid(row=grid_row, column=3, padx=3)
            ttk.Entry(self.block_table_inner, textvariable=cfg["action"], width=10).grid(row=grid_row, column=4, padx=3)
            ttk.Spinbox(self.block_table_inner, from_=0, to=90, textvariable=cfg["crop_right"], width=4).grid(row=grid_row, column=5, padx=3)
            ttk.Button(self.block_table_inner, text="✕", width=3, command=lambda bid=block_id: self._remove_block(bid)).grid(row=grid_row, column=6, padx=3)

    def on_export_blocks(self) -> None:
        if not self.anim_blocks:
            messagebox.showinfo("Экспорт блоков", "Сначала выдели хотя бы один блок анимации на холсте.")
            return

        marked = [
            (bid, cfg) for bid, cfg in sorted(self.anim_blocks.items())
            if cfg["role"].get().strip() and cfg["action"].get().strip()
        ]
        if not marked:
            messagebox.showinfo("Экспорт блоков", "Впиши роль и действие хотя бы для одного блока в таблице.")
            return

        out_dir = filedialog.askdirectory(title="Папка для сохранения кадров")
        if not out_dir:
            return

        saved = 0
        for bid, cfg in marked:
            role = cfg["role"].get()
            action = cfg["action"].get()
            crop_right = cfg["crop_right"].get()
            bg = cfg["bg_color"]
            r0, r1, c0, c1 = cfg["row_start"], cfg["row_end"], cfg["col_start"], cfg["col_end"]
            cells = [(r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)]
            total = len(cells)
            for idx, (row, col) in enumerate(cells):
                box = self._cell_box(row, col)
                if box is None:
                    continue
                processed = sc.process_cell(
                    self.sheet, box, bg,
                    tol=self.tol_var.get(), edge_tol=self.edge_tol_var.get(),
                    crop=(0.0, crop_right, 0.0, 0.0),
                )
                filename = sc.build_export_filename(role, action, idx, total)
                processed.save(os.path.join(out_dir, filename))
                saved += 1

        messagebox.showinfo("Экспорт завершён", f"Сохранено кадров: {saved} (блоков: {len(marked)})\nПапка: {out_dir}")

    # ------------------------------------------------------------- helpers
    def _redraw_canvas(self) -> None:
        self.canvas.delete("all")
        if self.sheet is None:
            return

        sw, sh = self.sheet.size
        scale = min(MAX_CANVAS_W / sw, MAX_CANVAS_H / sh, 1.0)
        self.display_scale = scale
        disp = self.sheet.resize((max(1, int(sw * scale)), max(1, int(sh * scale))), Image.NEAREST)
        self.canvas_img_ref = ImageTk.PhotoImage(disp)
        self.canvas.config(width=disp.width, height=disp.height)
        self.canvas.create_image(0, 0, anchor="nw", image=self.canvas_img_ref)

        # Рабочая область (если задана) — сетка рисуется только внутри неё
        if self.work_region:
            rx0, ry0, rx1, ry1 = [v * scale for v in self.work_region]
        else:
            rx0, ry0, rx1, ry1 = 0, 0, disp.width, disp.height

        # сетка
        for x in self.cols_boundaries:
            xd = x * scale
            self.canvas.create_line(xd, ry0, xd, ry1, fill="#ff5050", width=1)
        for y in self.rows_boundaries:
            yd = y * scale
            self.canvas.create_line(rx0, yd, rx1, yd, fill="#ff5050", width=1)

        if self.work_region:
            self.canvas.create_rectangle(rx0, ry0, rx1, ry1, outline="#4aa3ff", width=2)

        # уже размеченные блоки анимаций (оранжевым) — охватывают весь свой диапазон клеток
        for cfg in self.anim_blocks.values():
            box_tl = self._cell_box(cfg["row_start"], cfg["col_start"])
            box_br = self._cell_box(cfg["row_end"], cfg["col_end"])
            if box_tl is None or box_br is None:
                continue
            bx0, by0 = box_tl[0] * scale, box_tl[1] * scale
            bx1, by1 = box_br[2] * scale, box_br[3] * scale
            self.canvas.create_rectangle(bx0, by0, bx1, by1, outline="#ff9800", width=2)

        # подсветка выбранных кадров
        for (r, c) in self.selected_cells:
            box = self._cell_box(r, c)
            if box is None:
                continue
            x0, y0, x1, y1 = [v * scale for v in box]
            self.canvas.create_rectangle(x0, y0, x1, y1, outline="#4caf50", width=2)

        if self.preview_cell is not None:
            box = self._cell_box(*self.preview_cell)
            if box is not None:
                x0, y0, x1, y1 = [v * scale for v in box]
                self.canvas.create_rectangle(x0, y0, x1, y1, outline="#ffd54a", width=2)

    def _cell_box(self, row: int, col: int) -> tuple[int, int, int, int] | None:
        if row + 1 >= len(self.rows_boundaries) or col + 1 >= len(self.cols_boundaries):
            return None
        return (
            self.cols_boundaries[col],
            self.rows_boundaries[row],
            self.cols_boundaries[col + 1],
            self.rows_boundaries[row + 1],
        )

    def _grid_ready(self) -> bool:
        return self.sheet is not None and len(self.cols_boundaries) >= 2 and len(self.rows_boundaries) >= 2

    def _set_status(self, text: str) -> None:
        self.status_label.config(text=text)

    def _update_bg_swatch(self) -> None:
        hexcol = "#%02x%02x%02x" % self.bg_color
        self.bg_swatch.delete("all")
        self.bg_swatch.create_rectangle(0, 0, 22, 22, fill=hexcol, outline="#888")

    def _get_crop_tuple(self) -> tuple[float, float, float, float]:
        return (self.crop_left.get(), self.crop_right.get(), self.crop_top.get(), self.crop_bottom.get())

    # ------------------------------------------------------------- events
    def on_open(self) -> None:
        path = filedialog.askopenfilename(
            title="Выбери спрайт-лист",
            filetypes=[("Изображения", "*.png *.webp *.jpg *.jpeg"), ("Все файлы", "*.*")],
        )
        if not path:
            return
        try:
            img = Image.open(path).convert("RGBA")
        except Exception as exc:
            messagebox.showerror("Ошибка открытия", str(exc))
            return

        self.sheet = img
        self.sheet_path = path
        self.bg_color = sc.sample_bg_color(img)
        self._update_bg_swatch()
        self.cols_boundaries = []
        self.rows_boundaries = []
        self.selected_cells.clear()
        self.preview_cell = None
        self.work_region = None
        self.anim_blocks.clear()
        self.region_label.config(text="Область: весь лист")
        self._redraw_canvas()
        self._rebuild_block_table()

        # Огромные многосекционные атласы (разные анимации с разным фоном в одном PNG) почти
        # никогда не детектятся как единая сетка — и полный скан такого размера просто небыстрый.
        # Для них сразу просим выделить область вместо того, чтобы вхолостую гонять авто-детект.
        pixel_count = img.width * img.height
        if pixel_count > 4_000_000:
            self._set_status(
                f"{os.path.basename(path)} — {img.width}x{img.height}px, большой лист. "
                f"Выдели рабочую область (одну секцию анимации) и жми «Авто-детект сетки»."
            )
        else:
            self._set_status(f"{os.path.basename(path)} — {img.width}x{img.height}px")
            self.on_auto_detect()

    def on_pick_bg_manual(self) -> None:
        rgb, _ = colorchooser.askcolor(color="#%02x%02x%02x" % self.bg_color, title="Цвет фона")
        if rgb:
            self.bg_color = tuple(int(v) for v in rgb)
            self._update_bg_swatch()
            self.refresh_preview()

    def _on_canvas_press(self, event: tk.Event) -> None:
        if self.sheet is None:
            return
        self._press_pos = (event.x, event.y)
        if self.region_select_mode.get():
            self._drag_rect_id = self.canvas.create_rectangle(
                event.x, event.y, event.x, event.y, outline="#4aa3ff", width=2, dash=(4, 2)
            )
        elif self.block_select_mode.get() and self._grid_ready():
            self._drag_rect_id = self.canvas.create_rectangle(
                event.x, event.y, event.x, event.y, outline="#ff9800", width=2, dash=(2, 2)
            )

    def _on_canvas_drag(self, event: tk.Event) -> None:
        if self._drag_rect_id is not None and self._press_pos is not None and (self.region_select_mode.get() or self.block_select_mode.get()):
            x0, y0 = self._press_pos
            self.canvas.coords(self._drag_rect_id, x0, y0, event.x, event.y)

    def _on_canvas_release(self, event: tk.Event) -> None:
        if self.sheet is None or self._press_pos is None:
            self._press_pos = None
            return
        x0, y0 = self._press_pos
        self._press_pos = None

        if self.region_select_mode.get():
            if self._drag_rect_id is not None:
                self.canvas.delete(self._drag_rect_id)
                self._drag_rect_id = None
            dx0, dy0 = min(x0, event.x), min(y0, event.y)
            dx1, dy1 = max(x0, event.x), max(y0, event.y)
            if (dx1 - dx0) < 6 or (dy1 - dy0) < 6:
                return  # слишком маленькое выделение — вероятно случайный клик, игнорируем
            sx0 = max(0, int(dx0 / self.display_scale))
            sy0 = max(0, int(dy0 / self.display_scale))
            sx1 = min(self.sheet.width, int(dx1 / self.display_scale))
            sy1 = min(self.sheet.height, int(dy1 / self.display_scale))
            self._set_work_region(sx0, sy0, sx1, sy1)
            return

        if self.block_select_mode.get():
            if self._drag_rect_id is not None:
                self.canvas.delete(self._drag_rect_id)
                self._drag_rect_id = None
            if not self._grid_ready():
                messagebox.showinfo("Разметка блоками", "Сначала задай сетку (авто-детект или вручную).")
                return
            dx0, dy0 = min(x0, event.x), min(y0, event.y)
            dx1, dy1 = max(x0, event.x), max(y0, event.y)
            sx0, sy0 = dx0 / self.display_scale, dy0 / self.display_scale
            sx1, sy1 = dx1 / self.display_scale, dy1 / self.display_scale
            # "-1" по нижней/правой границе, чтобы клик ровно на линии сетки не захватывал
            # лишнюю соседнюю клетку (иначе выделение "переезжает" за край на 1 клетку)
            col_start = self._index_for(sx0, self.cols_boundaries)
            col_end = self._index_for(max(sx0, sx1 - 0.001), self.cols_boundaries)
            row_start = self._index_for(sy0, self.rows_boundaries)
            row_end = self._index_for(max(sy0, sy1 - 0.001), self.rows_boundaries)
            if col_start is None or col_end is None or row_start is None or row_end is None:
                return  # выделение целиком вне сетки (например, в поле за её пределами)
            self._add_block(min(row_start, row_end), max(row_start, row_end), min(col_start, col_end), max(col_start, col_end))
            return

        # Обычный (не-drag) клик — если мышь почти не сдвинулась между press и release
        if abs(event.x - x0) > 4 or abs(event.y - y0) > 4:
            return
        self._handle_cell_click(event.x / self.display_scale, event.y / self.display_scale)

    def _handle_cell_click(self, x: float, y: float) -> None:
        if self.pick_bg_mode.get():
            xi, yi = int(x), int(y)
            if 0 <= xi < self.sheet.width and 0 <= yi < self.sheet.height:
                sampled = self.sheet.convert("RGB").getpixel((xi, yi))
                if self._bg_pick_target_block is not None:
                    block = self.anim_blocks.get(self._bg_pick_target_block)
                    if block is not None:
                        block["bg_color"] = sampled
                        self._rebuild_block_table()
                    self._bg_pick_target_block = None
                else:
                    self.bg_color = sampled
                    self._update_bg_swatch()
                self.pick_bg_mode.set(False)
                self.refresh_preview()
            return

        if not self._grid_ready():
            return

        col = self._index_for(x, self.cols_boundaries)
        row = self._index_for(y, self.rows_boundaries)
        if col is None or row is None:
            return

        cell = (row, col)
        if cell in self.selected_cells:
            del self.selected_cells[cell]
        else:
            self.selected_cells[cell] = True
        self.preview_cell = cell
        self._update_selection_label()
        self._redraw_canvas()
        self.refresh_preview()

    def _set_work_region(self, x0: int, y0: int, x1: int, y1: int) -> None:
        if x1 - x0 < 4 or y1 - y0 < 4:
            return
        self.work_region = (x0, y0, x1, y1)
        self.cols_boundaries = []
        self.rows_boundaries = []
        self.selected_cells.clear()
        self.preview_cell = None
        self.region_label.config(text=f"Область: ({x0},{y0})–({x1},{y1}), {x1 - x0}×{y1 - y0}px")
        self._set_status("Область выделена — жми «Авто-детект сетки» или задай строки/колонки вручную")
        self._redraw_canvas()
        self._rebuild_block_table()

    def on_reset_region(self) -> None:
        self.work_region = None
        self.cols_boundaries = []
        self.rows_boundaries = []
        self.selected_cells.clear()
        self.preview_cell = None
        self.anim_blocks.clear()
        self.region_label.config(text="Область: весь лист")
        self._set_status("Область сброшена — работаем по всему листу")
        self._redraw_canvas()
        self._rebuild_block_table()

    @staticmethod
    def _index_for(pos: float, boundaries: list[int]) -> int | None:
        for i in range(len(boundaries) - 1):
            if boundaries[i] <= pos < boundaries[i + 1]:
                return i
        return None

    def _region_bounds(self) -> tuple[int, int, int, int]:
        """Границы, в которых сейчас работаем: заданная область или весь лист."""
        if self.work_region:
            return self.work_region
        return (0, 0, self.sheet.width, self.sheet.height)

    def on_auto_detect(self) -> None:
        if self.sheet is None:
            return
        rx0, ry0, rx1, ry1 = self._region_bounds()
        region_img = self.sheet.crop((rx0, ry0, rx1, ry1))
        thr = self.detect_threshold.get()
        cols = sc.detect_grid_axis(region_img, self.bg_color, axis="col", threshold=thr, min_gap=6)
        rows = sc.detect_grid_axis(region_img, self.bg_color, axis="row", threshold=thr, min_gap=6)

        if cols.cell_count < 1 or rows.cell_count < 1:
            messagebox.showwarning(
                "Авто-детект",
                "Не удалось найти сетку — поправь цвет фона, чувствительность, "
                "или выдели рабочую область поменьше (один блок анимации).",
            )
            return

        # Сдвигаем локальные границы области обратно в координаты полного листа —
        # дальше весь код (cell_box, экспорт) всегда работает в координатах self.sheet.
        self.cols_boundaries = [b + rx0 for b in cols.boundaries]
        self.rows_boundaries = [b + ry0 for b in rows.boundaries]
        self.cols_var.set(cols.cell_count)
        self.rows_var.set(rows.cell_count)
        self.selected_cells.clear()
        self.preview_cell = None
        self.anim_blocks.clear()  # индексы клеток старых блоков больше не действительны при новой сетке
        where = ", в области" if self.work_region else ""
        self._set_status(f"{os.path.basename(self.sheet_path)} — сетка {cols.cell_count}x{rows.cell_count} (авто{where})")
        self._update_selection_label()
        self._redraw_canvas()
        self._rebuild_block_table()

    def on_manual_grid_change(self) -> None:
        if self.sheet is None:
            return
        rx0, ry0, rx1, ry1 = self._region_bounds()
        cols_n = max(1, self.cols_var.get())
        rows_n = max(1, self.rows_var.get())
        self.cols_boundaries = [b + rx0 for b in sc.uniform_boundaries(rx1 - rx0, cols_n)]
        self.rows_boundaries = [b + ry0 for b in sc.uniform_boundaries(ry1 - ry0, rows_n)]
        self.selected_cells = {(r, c): True for (r, c) in self.selected_cells if r < rows_n and c < cols_n}
        self.anim_blocks.clear()  # индексы клеток старых блоков больше не действительны при новой сетке
        where = ", в области" if self.work_region else ""
        self._set_status(f"{os.path.basename(self.sheet_path)} — сетка {cols_n}x{rows_n} (вручную, равномерно{where})")
        self._update_selection_label()
        self._redraw_canvas()
        self.refresh_preview()
        self._rebuild_block_table()

    def on_select_all(self) -> None:
        if not self._grid_ready():
            return
        n_rows = len(self.rows_boundaries) - 1
        n_cols = len(self.cols_boundaries) - 1
        self.selected_cells = {(r, c): True for r in range(n_rows) for c in range(n_cols)}
        self._update_selection_label()
        self._redraw_canvas()

    def on_select_none(self) -> None:
        self.selected_cells.clear()
        self._update_selection_label()
        self._redraw_canvas()

    def _update_selection_label(self) -> None:
        self.sel_count_label.config(text=f"Выбрано: {len(self.selected_cells)}")
        self._update_export_preview()
        self._stop_playback()

    def refresh_preview(self) -> None:
        if self.preview_cell is None or not self._grid_ready():
            return
        row, col = self.preview_cell
        box = self._cell_box(row, col)
        if box is None:
            return

        raw_cell = self.sheet.crop(box).convert("RGBA")
        processed = sc.process_cell(
            self.sheet, box, self.bg_color,
            tol=self.tol_var.get(), edge_tol=self.edge_tol_var.get(),
            crop=self._get_crop_tuple(),
        )

        self.preview_img_refs.clear()

        before_disp = self._fit_for_preview(raw_cell, 130)
        self.preview_before_cv.delete("all")
        tkimg1 = ImageTk.PhotoImage(before_disp)
        self.preview_img_refs.append(tkimg1)
        self.preview_before_cv.create_image(70, 70, image=tkimg1)

        after_disp = self._fit_for_preview(processed, 130)
        self.preview_after_cv.delete("all")
        tkimg2 = ImageTk.PhotoImage(after_disp)
        self.preview_img_refs.append(tkimg2)
        self.preview_after_cv.create_image(70, 70, image=tkimg2)

        game_scale = sc.resize_to_height(processed, 12.0)
        scaled_x8 = game_scale.resize((game_scale.width * 8, game_scale.height * 8), Image.NEAREST)
        scaled_disp = self._fit_for_preview(scaled_x8, 130)
        self.preview_scaled_cv.delete("all")
        tkimg3 = ImageTk.PhotoImage(scaled_disp)
        self.preview_img_refs.append(tkimg3)
        self.preview_scaled_cv.create_image(70, 70, image=tkimg3)

        self.preview_dims_label.config(
            text=f"исходный кадр {raw_cell.width}×{raw_cell.height} → обработан {processed.width}×{processed.height} → игра ~12px высотой"
        )

    @staticmethod
    def _fit_for_preview(img: Image.Image, box: int) -> Image.Image:
        w, h = img.size
        if w == 0 or h == 0:
            return Image.new("RGBA", (box, box), (0, 0, 0, 0))
        scale = min(box / w, box / h)
        nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
        return img.resize((nw, nh), Image.NEAREST)

    def _update_export_preview(self) -> None:
        if not hasattr(self, "export_preview_label"):
            return  # ещё не построен UI на момент первого вызова из trace
        total = max(1, len(self.selected_cells))
        unit = self.unit_type_var.get()
        action = self.action_var.get()
        names = [sc.build_export_filename(unit, action, i, total) for i in range(min(total, 3))]
        suffix = ", …" if total > 3 else ""
        self.export_preview_label.config(text=f"Пример ({total} шт.): {', '.join(names)}{suffix}")

    def on_export(self) -> None:
        if not self.selected_cells:
            messagebox.showinfo("Экспорт", "Сначала выбери хотя бы один кадр (клик по нему на листе).")
            return
        out_dir = filedialog.askdirectory(title="Папка для сохранения кадров")
        if not out_dir:
            return

        crop = self._get_crop_tuple()
        unit = self.unit_type_var.get()
        action = self.action_var.get()
        cells = list(self.selected_cells)  # порядок клика — важен для букв-вариантов a/b/c
        total = len(cells)
        saved = 0
        for i, (row, col) in enumerate(cells):
            box = self._cell_box(row, col)
            if box is None:
                continue
            processed = sc.process_cell(self.sheet, box, self.bg_color, tol=self.tol_var.get(), edge_tol=self.edge_tol_var.get(), crop=crop)
            filename = sc.build_export_filename(unit, action, i, total)
            out_path = os.path.join(out_dir, filename)
            processed.save(out_path)
            saved += 1

        messagebox.showinfo("Экспорт завершён", f"Сохранено кадров: {saved}\nПапка: {out_dir}")

    # --------------------------------------------------------- проигрыватель
    def on_play_toggle(self) -> None:
        if self.is_playing:
            self._stop_playback()
            return
        if not self.selected_cells:
            messagebox.showinfo("Проигрыватель", "Сначала выбери хотя бы один кадр (клик по нему на листе).")
            return
        self.is_playing = True
        self.play_index = 0
        self.play_btn.config(text="⏸ Стоп")
        self._play_tick()

    def _stop_playback(self) -> None:
        if self.play_job_id is not None:
            self.root.after_cancel(self.play_job_id)
            self.play_job_id = None
        if self.is_playing:
            self.is_playing = False
            self.play_btn.config(text="▶ Играть")

    def _play_tick(self) -> None:
        cells = list(self.selected_cells)
        if not cells:
            self._stop_playback()
            return

        self.play_index %= len(cells)
        row, col = cells[self.play_index]
        box = self._cell_box(row, col)
        if box is not None:
            processed = sc.process_cell(
                self.sheet, box, self.bg_color,
                tol=self.tol_var.get(), edge_tol=self.edge_tol_var.get(),
                crop=self._get_crop_tuple(),
            )
            true_size = sc.resize_to_height(processed, 12.0)
            mag = true_size.resize((true_size.width * 10, true_size.height * 10), Image.NEAREST)

            self.play_img_refs.clear()

            true_disp = self._fit_for_preview(true_size, 130)
            self.play_true_cv.delete("all")
            tkimg_a = ImageTk.PhotoImage(true_disp)
            self.play_img_refs.append(tkimg_a)
            self.play_true_cv.create_image(70, 50, image=tkimg_a)

            mag_disp = self._fit_for_preview(mag, 130)
            self.play_mag_cv.delete("all")
            tkimg_b = ImageTk.PhotoImage(mag_disp)
            self.play_img_refs.append(tkimg_b)
            self.play_mag_cv.create_image(70, 50, image=tkimg_b)

            self.play_frame_label.config(text=f"кадр {self.play_index + 1}/{len(cells)}")

        self.play_index += 1
        fps = max(1, self.fps_var.get())
        self.play_job_id = self.root.after(int(1000 / fps), self._play_tick)


def main() -> None:
    root = tk.Tk()
    try:
        style = ttk.Style()
        if "clam" in style.theme_names():
            style.theme_use("clam")
    except Exception:
        pass
    app = SpriteSlicerApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
