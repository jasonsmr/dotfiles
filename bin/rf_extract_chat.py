#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
export_chats.py
Extract ChatGPT sessions from an export folder into per-session folders
with Markdown + JSONL "memory" for quick reference.

Usage:
  python export_chats.py --source /sdcard/Download/your_export_dir --out ./extracted_chats
  python export_chats.py --all
  python export_chats.py --filter "robotforest"

Notes:
- Designed to tolerate older/newer OpenAI export schemas.
- Primary sources: conversations.json, shared_conversations.json (if present).
- Creates:
    extracted_chats/
      index.json
      index.md
      <YYYY-MM-DD_HHMMSS>__<slug>__<short-id>/
        transcript.md
        memory.jsonl
        metadata.json
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# --------- Helpers ---------
def p(s: str):
    print(s, flush=True)

def slugify(name: str, max_len: int = 60) -> str:
    name = name.strip().lower()
    # replace emojis and non-word chars with dash
    name = re.sub(r"[^\w\s-]", "", name, flags=re.UNICODE)
    name = re.sub(r"\s+", "-", name)
    name = re.sub(r"-{2,}", "-", name)
    name = name.strip("-_")
    return name[:max_len] or "untitled"

def safe_dt(ts: Optional[float]) -> Optional[datetime]:
    if ts is None:
        return None
    try:
        # exports can be seconds (float) since epoch
        return datetime.fromtimestamp(float(ts))
    except Exception:
        return None

def fmt_dt(dt: Optional[datetime]) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S") if dt else "unknown"

def short_id(s: str) -> str:
    return s[:8] if s else "noid"

def load_json_if_exists(path: Path) -> Optional[Any]:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            p(f"[warn] Failed to parse JSON: {path} ({e})")
    return None

def ensure_dir(d: Path):
    d.mkdir(parents=True, exist_ok=True)

def join_parts(content: Any) -> str:
    """
    Try to normalize message content across schema varieties.
    """
    if content is None:
        return ""
    # Newer export: {"content": {"content_type": "text", "parts": ["..."]}}
    if isinstance(content, dict):
        if "parts" in content and isinstance(content["parts"], list):
            return "\n".join([str(x) for x in content["parts"] if x is not None])
        # Sometimes already a string in 'text' or similar
        for key in ("text", "value", "content"):
            v = content.get(key)
            if isinstance(v, str):
                return v
            if isinstance(v, list):
                return "\n".join([str(x) for x in v if x is not None])
    # Older export could be a list of parts only
    if isinstance(content, list):
        return "\n".join([str(x) for x in content if x is not None])
    # Already a string
    if isinstance(content, str):
        return content
    return str(content)

def collect_messages_from_mapping(mapping: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Given the 'mapping' dict from a conversation export,
    produce a list of messages ordered by create_time (if available),
    filtered to roles of interest.
    """
    msgs = []
    for _id, node in mapping.items():
        msg = node.get("message") if isinstance(node, dict) else None
        if not msg:
            continue
        author = (msg.get("author") or {}).get("role")
        if author not in {"system", "user", "assistant", "tool"}:
            continue
        create_time = msg.get("create_time")
        content = msg.get("content")
        text = join_parts(content)
        if not text and author == "tool":
            # tool messages can be bulky; keep as-is anyway
            text = json.dumps(content, ensure_ascii=False)
        msgs.append({
            "id": msg.get("id") or _id,
            "author": author,
            "create_time": create_time,
            "text": text,
        })
    # Order by time, falling back to stable id order
    msgs.sort(key=lambda m: (m["create_time"] if m["create_time"] is not None else float("inf"), m["id"]))
    return msgs

def extract_sessions_from_conversations(convos_json: Any) -> List[Dict[str, Any]]:
    """
    Handle the common OpenAI export conversations.json schema.
    It is usually a list of conversation objects.
    """
    sessions = []
    if not isinstance(convos_json, list):
        return sessions

    for conv in convos_json:
        conv_id = conv.get("id") or conv.get("conversation_id") or ""
        title = conv.get("title") or "Untitled"
        create_ts = conv.get("create_time") or conv.get("create_time_ts")
        update_ts = conv.get("update_time") or conv.get("update_time_ts")
        mapping = conv.get("mapping") or {}

        msgs = collect_messages_from_mapping(mapping)
        first_ts = safe_dt(create_ts or (msgs[0]["create_time"] if msgs and msgs[0]["create_time"] else None))
        last_ts = safe_dt(update_ts or (msgs[-1]["create_time"] if msgs and msgs[-1]["create_time"] else None))

        sessions.append({
            "source": "conversations.json",
            "id": conv_id or "",
            "title": title,
            "created_at": fmt_dt(first_ts),
            "updated_at": fmt_dt(last_ts),
            "created_dt": first_ts,
            "updated_dt": last_ts,
            "messages": msgs,
        })
    return sessions

def extract_sessions_from_shared(shared_json: Any) -> List[Dict[str, Any]]:
    """
    Handle shared_conversations.json if present.
    Shape can vary; we try to be forgiving.
    """
    sessions = []
    if not isinstance(shared_json, list):
        return sessions

    for item in shared_json:
        conv_id = item.get("id") or item.get("conversation_id") or ""
        title = item.get("title") or "Untitled (shared)"
        # Some shared exports embed 'mapping' directly; sometimes it's under 'conversation'
        mapping = item.get("mapping") or (item.get("conversation") or {}).get("mapping") or {}
        create_ts = item.get("create_time") or (item.get("conversation") or {}).get("create_time")
        update_ts = item.get("update_time") or (item.get("conversation") or {}).get("update_time")

        msgs = collect_messages_from_mapping(mapping)
        first_ts = safe_dt(create_ts or (msgs[0]["create_time"] if msgs and msgs[0]["create_time"] else None))
        last_ts = safe_dt(update_ts or (msgs[-1]["create_time"] if msgs and msgs[-1]["create_time"] else None))

        sessions.append({
            "source": "shared_conversations.json",
            "id": conv_id or "",
            "title": title,
            "created_at": fmt_dt(first_ts),
            "updated_at": fmt_dt(last_ts),
            "created_dt": first_ts,
            "updated_dt": last_ts,
            "messages": msgs,
        })
    return sessions

def render_markdown_transcript(session: Dict[str, Any]) -> str:
    header = [
        f"# {session['title']}",
        "",
        f"- **ID:** `{session['id'] or 'unknown'}`",
        f"- **Source:** {session.get('source','')}",
        f"- **Created:** {session['created_at']}",
        f"- **Updated:** {session['updated_at']}",
        "",
        "---",
        "",
    ]
    lines = header
    for m in session["messages"]:
        dt = safe_dt(m.get("create_time"))
        when = fmt_dt(dt)
        role = m.get("author", "unknown")
        text = m.get("text", "")
        # Fence assistant/user differently for readability
        lines.append(f"## {when} — {role}")
        lines.append("")
        # Preserve code blocks already present; otherwise just print text
        lines.append(text if text else "_(empty)_")
        lines.append("")
        lines.append("---")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"

def write_session(out_root: Path, session: Dict[str, Any]) -> Dict[str, str]:
    # Build folder name
    stamp = session["created_dt"] or session["updated_dt"]
    stamp_str = stamp.strftime("%Y-%m-%d_%H%M%S") if stamp else "unknown"
    folder = f"{stamp_str}__{slugify(session['title'])}__{short_id(session['id'])}"
    sess_dir = out_root / folder
    ensure_dir(sess_dir)

    # transcript.md
    transcript = render_markdown_transcript(session)
    (sess_dir / "transcript.md").write_text(transcript, encoding="utf-8")

    # memory.jsonl (one message per line)
    with (sess_dir / "memory.jsonl").open("w", encoding="utf-8") as f:
        for m in session["messages"]:
            obj = {
                "ts": m.get("create_time"),
                "when": fmt_dt(safe_dt(m.get("create_time"))),
                "role": m.get("author", ""),
                "text": m.get("text", ""),
            }
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    # metadata.json
    meta = {
        "id": session["id"],
        "title": session["title"],
        "source": session["source"],
        "created_at": session["created_at"],
        "updated_at": session["updated_at"],
        "message_count": len(session["messages"]),
        "folder": folder,
    }
    (sess_dir / "metadata.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    return {"folder": folder, "transcript": "transcript.md", "memory": "memory.jsonl", "metadata": "metadata.json"}

def print_table(sessions: List[Dict[str, Any]]) -> None:
    p("")
    p("Found sessions:")
    p("Idx | Created              | Updated              | Messages | Title")
    p("----+----------------------+----------------------+----------+------------------------")
    for i, s in enumerate(sessions):
        p(f"{i:>3} | {s['created_at']:<20} | {s['updated_at']:<20} | {len(s['messages']):>8} | {s['title'][:60]}")

def parse_selection(inp: str, max_idx: int) -> List[int]:
    inp = inp.strip().lower()
    if inp in ("all", "a", "*"):
        return list(range(max_idx + 1))
    selected: List[int] = []
    for part in inp.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            try:
                a, b = int(a), int(b)
                for x in range(min(a, b), max(a, b) + 1):
                    if 0 <= x <= max_idx:
                        selected.append(x)
            except ValueError:
                continue
        else:
            try:
                x = int(part)
                if 0 <= x <= max_idx:
                    selected.append(x)
            except ValueError:
                continue
    # de-dup while preserving order
    seen = set()
    out = []
    for x in selected:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out

# --------- Main CLI ---------
def main():
    ap = argparse.ArgumentParser(description="Extract ChatGPT conversations to per-session folders.")
    ap.add_argument("--source", "-s", type=str, default=".", help="Path to export folder (contains conversations.json, etc.)")
    ap.add_argument("--out", "-o", type=str, default="./extracted_chats", help="Output folder")
    ap.add_argument("--all", action="store_true", help="Export all sessions (non-interactive)")
    ap.add_argument("--filter", type=str, default="", help="Case-insensitive substring filter on title")
    args = ap.parse_args()

    src = Path(args.source).resolve()
    out_root = Path(args.out).resolve()
    ensure_dir(out_root)

    convos = load_json_if_exists(src / "conversations.json") or []
    shared = load_json_if_exists(src / "shared_conversations.json") or []

    sessions = extract_sessions_from_conversations(convos) + extract_sessions_from_shared(shared)

    # If nothing in JSON, try fallback to conversations.json within "conversations" key (rare)
    if not sessions and isinstance(convos, dict) and "conversations" in convos:
        sessions = extract_sessions_from_conversations(convos.get("conversations") or [])

    # Filter by title if requested
    if args.filter:
        q = args.filter.lower()
        sessions = [s for s in sessions if q in (s["title"] or "").lower()]

    # Sort by created_dt desc for nicer listing
    sessions.sort(key=lambda s: (s["created_dt"] or datetime.min), reverse=True)

    if not sessions:
        p(f"[error] No sessions found in {src}")
        sys.exit(1)

    print_table(sessions)

    if args.all:
        selection = list(range(len(sessions)))
    else:
        p("")
        p("Select sessions to export:")
        p(" - Enter 'all' to export everything")
        p(" - Or give indices like '0,2,5-8'")
        sel = input("Your choice: ").strip()
        selection = parse_selection(sel, len(sessions) - 1)
        if not selection:
            p("[warn] Nothing selected. Exiting.")
            sys.exit(0)

    exported = []
    for idx in selection:
        session = sessions[idx]
        res = write_session(out_root, session)
        exported.append({
            "index": idx,
            "id": session["id"],
            "title": session["title"],
            "created_at": session["created_at"],
            "updated_at": session["updated_at"],
            "message_count": len(session["messages"]),
            "folder": res["folder"],
        })
        p(f"[ok] Exported: {session['title']}  ->  {res['folder']}")

    # Root indices
    (out_root / "index.json").write_text(json.dumps(exported, indent=2, ensure_ascii=False), encoding="utf-8")

    # Also a Markdown index
    md = ["# Chat Exports Index", ""]
    for item in exported:
        md.append(f"## {item['title']}")
        md.append(f"- **Folder**: `{item['folder']}`")
        md.append(f"- **Messages**: {item['message_count']}")
        md.append(f"- **Created**: {item['created_at']}  |  **Updated**: {item['updated_at']}")
        md.append("")
    (out_root / "index.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    p("")
    p(f"[done] Exported {len(exported)} session(s) to: {out_root}")
    p("Artifacts per session: transcript.md, memory.jsonl, metadata.json")
    p("Root: index.json, index.md")


if __name__ == "__main__":
    main()
