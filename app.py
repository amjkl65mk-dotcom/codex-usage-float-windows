from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import tkinter as tk


APP_NAME = "Codex 用量悬浮窗"
CONFIG_DIR = Path(os.getenv("APPDATA", Path.home())) / "CodexUsageFloat"
CONFIG_FILE = CONFIG_DIR / "config.json"
CODEX_HOME = Path(os.getenv("CODEX_HOME", Path.home() / ".codex"))


@dataclass
class Usage:
    used_percent: float
    resets_at: int | None
    window_minutes: int | None
    plan_type: str | None
    source: Path
    observed_at: float

    @property
    def remaining_percent(self) -> float:
        return max(0.0, min(100.0, 100.0 - self.used_percent))


def iter_session_files(root: Path):
    candidates: list[Path] = []
    for folder in (root / "sessions", root / "archived_sessions"):
        if folder.exists():
            candidates.extend(folder.rglob("*.jsonl"))
    yield from sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)


def read_latest_usage(root: Path = CODEX_HOME, max_files: int = 40) -> Usage | None:
    newest: Usage | None = None
    for path in list(iter_session_files(root))[:max_files]:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                lines = handle.readlines()
            for line in reversed(lines):
                if '"type":"token_count"' not in line or '"rate_limits"' not in line:
                    continue
                row = json.loads(line)
                payload = row.get("payload") or {}
                limits = payload.get("rate_limits") or {}
                primary = limits.get("primary") or {}
                used = primary.get("used_percent")
                if used is None:
                    continue
                stamp = row.get("timestamp")
                observed = path.stat().st_mtime
                if stamp:
                    try:
                        observed = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
                    except ValueError:
                        pass
                item = Usage(
                    used_percent=float(used),
                    resets_at=primary.get("resets_at"),
                    window_minutes=primary.get("window_minutes"),
                    plan_type=limits.get("plan_type"),
                    source=path,
                    observed_at=observed,
                )
                if newest is None or item.observed_at > newest.observed_at:
                    newest = item
                break
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            continue
    return newest


def load_config() -> dict:
    defaults = {"x": None, "y": 36, "opacity": 0.93, "refresh_seconds": 30, "compact": False}
    try:
        defaults.update(json.loads(CONFIG_FILE.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError):
        pass
    return defaults


def save_config(config: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")


def format_reset(epoch: int | None) -> str:
    if not epoch:
        return "重置时间未知"
    remaining = max(0, epoch - int(time.time()))
    days, remaining = divmod(remaining, 86400)
    hours, remaining = divmod(remaining, 3600)
    minutes = remaining // 60
    if days:
        countdown = f"{days}天 {hours}小时"
    elif hours:
        countdown = f"{hours}小时 {minutes}分"
    else:
        countdown = f"{minutes}分钟"
    local = datetime.fromtimestamp(epoch).strftime("%m-%d %H:%M")
    return f"{countdown}后重置 · {local}"


class UsageFloat(tk.Tk):
    def __init__(self):
        super().__init__()
        self.config_data = load_config()
        self._drag_origin = None
        self._after_id = None
        self.title(APP_NAME)
        self.overrideredirect(True)
        self.attributes("-topmost", True)
        self.attributes("-alpha", float(self.config_data["opacity"]))
        self.configure(bg="#111827")
        self._build_ui()
        self.update_idletasks()
        x = self.config_data.get("x")
        if x is None:
            x = self.winfo_screenwidth() - self.winfo_reqwidth() - 24
        self.geometry(f"+{int(x)}+{int(self.config_data.get('y', 36))}")
        self.bind("<ButtonPress-1>", self._start_drag)
        self.bind("<B1-Motion>", self._drag)
        self.bind("<ButtonRelease-1>", self._end_drag)
        self.bind("<Double-Button-1>", lambda _e: self.toggle_compact())
        self.bind("<Button-3>", self.show_menu)
        self.refresh()

    def _build_ui(self):
        self.card = tk.Frame(self, bg="#111827", padx=15, pady=12)
        self.card.pack(fill="both", expand=True)
        self.title_label = tk.Label(self.card, text="CODEX · 剩余用量", bg="#111827", fg="#9CA3AF", font=("Segoe UI", 9, "bold"))
        self.title_label.pack(anchor="w")
        self.value_label = tk.Label(self.card, text="--%", bg="#111827", fg="#F9FAFB", font=("Segoe UI", 25, "bold"))
        self.value_label.pack(anchor="w", pady=(1, 3))
        self.canvas = tk.Canvas(self.card, width=206, height=7, bg="#263244", highlightthickness=0)
        self.canvas.pack()
        self.bar = self.canvas.create_rectangle(0, 0, 0, 7, fill="#34D399", width=0)
        self.detail_label = tk.Label(self.card, text="正在读取本机 Codex 数据…", bg="#111827", fg="#9CA3AF", font=("Segoe UI", 8))
        self.detail_label.pack(anchor="w", pady=(7, 0))
        self.menu = tk.Menu(self, tearoff=False)
        self.menu.add_command(label="立即刷新", command=self.refresh)
        self.menu.add_command(label="切换紧凑模式", command=self.toggle_compact)
        self.menu.add_separator()
        self.menu.add_command(label="退出", command=self.close)

    def show_menu(self, event):
        self.menu.tk_popup(event.x_root, event.y_root)

    def _start_drag(self, event):
        self._drag_origin = (event.x_root, event.y_root, self.winfo_x(), self.winfo_y())

    def _drag(self, event):
        if self._drag_origin:
            sx, sy, wx, wy = self._drag_origin
            self.geometry(f"+{wx + event.x_root - sx}+{wy + event.y_root - sy}")

    def _end_drag(self, _event):
        self._drag_origin = None
        self.config_data.update({"x": self.winfo_x(), "y": self.winfo_y()})
        save_config(self.config_data)

    def toggle_compact(self):
        compact = not bool(self.config_data.get("compact"))
        self.config_data["compact"] = compact
        if compact:
            self.title_label.pack_forget()
            self.canvas.pack_forget()
            self.detail_label.pack_forget()
            self.card.configure(padx=12, pady=5)
            self.value_label.configure(font=("Segoe UI", 13, "bold"))
        else:
            self.card.configure(padx=15, pady=12)
            self.title_label.pack(anchor="w", before=self.value_label)
            self.value_label.configure(font=("Segoe UI", 25, "bold"))
            self.canvas.pack(after=self.value_label)
            self.detail_label.pack(anchor="w", pady=(7, 0), after=self.canvas)
        save_config(self.config_data)

    def refresh(self):
        usage = read_latest_usage()
        if usage:
            remaining = usage.remaining_percent
            color = "#34D399" if remaining > 40 else "#FBBF24" if remaining > 20 else "#F87171"
            self.value_label.configure(text=f"{remaining:.0f}%", fg=color)
            self.canvas.coords(self.bar, 0, 0, 206 * remaining / 100, 7)
            self.canvas.itemconfigure(self.bar, fill=color)
            plan = usage.plan_type.upper() if usage.plan_type else "CHATGPT"
            self.title_label.configure(text=f"CODEX {plan} · 剩余用量")
            self.detail_label.configure(text=format_reset(usage.resets_at))
        else:
            self.value_label.configure(text="--%", fg="#9CA3AF")
            self.detail_label.configure(text="暂无数据 · 在 Codex 中发送一条消息后刷新")
        if self._after_id:
            self.after_cancel(self._after_id)
        self._after_id = self.after(int(self.config_data["refresh_seconds"]) * 1000, self.refresh)

    def close(self):
        self.config_data.update({"x": self.winfo_x(), "y": self.winfo_y()})
        save_config(self.config_data)
        self.destroy()


def main():
    if sys.platform != "win32":
        print("此版本面向 Windows，但在带 Tk 的系统上也可运行。")
    app = UsageFloat()
    if app.config_data.get("compact"):
        app.config_data["compact"] = False
        app.toggle_compact()
    app.mainloop()


if __name__ == "__main__":
    main()
