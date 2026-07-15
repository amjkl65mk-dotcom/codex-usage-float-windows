import json
from pathlib import Path

from app import format_reset, read_latest_usage


def test_read_latest_usage(tmp_path: Path):
    folder = tmp_path / "sessions" / "2026" / "07" / "15"
    folder.mkdir(parents=True)
    row = {
        "timestamp": "2026-07-15T05:00:00Z",
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "primary": {"used_percent": 37.0, "window_minutes": 10080, "resets_at": 2000000000},
                "plan_type": "plus",
            },
        },
    }
    (folder / "rollout.jsonl").write_text(json.dumps(row) + "\n", encoding="utf-8")
    usage = read_latest_usage(tmp_path)
    assert usage is not None
    assert usage.remaining_percent == 63.0
    assert usage.plan_type == "plus"
    assert usage.window_minutes == 10080


def test_format_reset_unknown():
    assert format_reset(None) == "重置时间未知"
