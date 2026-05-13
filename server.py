#!/usr/bin/env python3
"""Hermes Chat 后端服务器（多线程版）"""
import json, os, sys, socketserver, sqlite3, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from threading import Thread

STATIC_DIR = os.path.join(os.path.dirname(__file__), "build", "web")
HERMES_HOME = os.path.expanduser("~/.hermes")

# 尝试导入 SessionDB
_session_db = None
try:
    sys.path.insert(0, os.path.join(HERMES_HOME, "hermes-agent"))
    from hermes_state import SessionDB
    _session_db = SessionDB()
except Exception:
    pass

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".json": "application/json",
    ".wasm": "application/wasm",
}


class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self._ok("", "text/plain")

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/api/sessions":
            return self._sessions()
        if p.startswith("/api/sessions/") and p.endswith("/messages"):
            sid = p.split("/")[3]
            return self._session_messages(sid)
        if p == "/api/stats":
            return self._stats()
        if p == "/api/stats/daily":
            return self._daily_stats()
        if p == "/api/health":
            return self._ok('{"status":"ok"}', "application/json")
        return self._static()

    def do_POST(self):
        p = urlparse(self.path).path
        if p.startswith("/api/sessions/") and p.endswith("/rename"):
            sid = p.split("/")[3]
            return self._rename_session(sid)
        self._ok('{"error":"not found"}', "application/json")

    def _ok(self, body, ctype):
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body.encode() if isinstance(body, str) else body)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def _sessions(self):
        limit = int(parse_qs(urlparse(self.path).query).get("limit", [50])[0])
        try:
            if _session_db:
                data = _session_db.list_sessions_rich(limit=limit, order_by_last_active=True)
                # 精简字段：只保留前端需要的
                KEEP = {"id","title","preview","source","model","message_count",
                        "input_tokens","output_tokens","cache_read_tokens","cache_write_tokens",
                        "started_at","last_active"}
                for s in data:
                    for k in list(s.keys()):
                        if k not in KEEP:
                            del s[k]
            else:
                data = []
        except Exception as e:
            data = {"error": str(e)}
        self._ok(json.dumps(data, ensure_ascii=False, default=str), "application/json")

    def _stats(self):
        stats = {"total_sessions": 0, "today_sessions": 0, "today_messages": 0,
                 "today_input_tokens": 0, "today_output_tokens": 0,
                 "today_cache_read": 0, "today_cache_write": 0,
                 "total_input_tokens": 0, "total_output_tokens": 0,
                 "total_cache_read": 0, "total_cache_write": 0}
        try:
            if _session_db:
                conn = _session_db._conn
                today_start = time.time() - time.time() % 86400
                # 总览
                row = conn.execute("SELECT COUNT(*) AS cnt, "
                    "COALESCE(SUM(input_tokens),0) AS inp, "
                    "COALESCE(SUM(output_tokens),0) AS outp, "
                    "COALESCE(SUM(cache_read_tokens),0) AS cr, "
                    "COALESCE(SUM(cache_write_tokens),0) AS cw "
                    "FROM sessions").fetchone()
                stats["total_sessions"] = row["cnt"]
                stats["total_input_tokens"] = row["inp"]
                stats["total_output_tokens"] = row["outp"]
                stats["total_cache_read"] = row["cr"]
                stats["total_cache_write"] = row["cw"]
                # 今日
                row = conn.execute("SELECT COUNT(*) AS cnt, "
                    "COALESCE(SUM(message_count),0) AS msgs, "
                    "COALESCE(SUM(input_tokens),0) AS inp, "
                    "COALESCE(SUM(output_tokens),0) AS outp, "
                    "COALESCE(SUM(cache_read_tokens),0) AS cr, "
                    "COALESCE(SUM(cache_write_tokens),0) AS cw "
                    "FROM sessions WHERE started_at >= ?",
                    (today_start,)).fetchone()
                stats["today_sessions"] = row["cnt"]
                stats["today_messages"] = row["msgs"]
                stats["today_input_tokens"] = row["inp"]
                stats["today_output_tokens"] = row["outp"]
                stats["today_cache_read"] = row["cr"]
                stats["today_cache_write"] = row["cw"]
        except Exception as e:
            stats["error"] = str(e)
        self._ok(json.dumps(stats, ensure_ascii=False, default=str), "application/json")

    def _daily_stats(self):
        from urllib.parse import parse_qs
        params = parse_qs(urlparse(self.path).query)
        days = int(params.get("days", [30])[0])
        result = []
        try:
            if _session_db:
                conn = _session_db._conn
                today = int(time.time())
                for d in range(days - 1, -1, -1):
                    day_start = today - (today % 86400) - d * 86400
                    day_end = day_start + 86400
                    row = conn.execute("SELECT "
                        "COALESCE(SUM(input_tokens),0) AS inp, "
                        "COALESCE(SUM(output_tokens),0) AS outp, "
                        "COALESCE(SUM(cache_read_tokens),0) AS cr, "
                        "COALESCE(SUM(cache_write_tokens),0) AS cw, "
                        "COUNT(*) AS cnt "
                        "FROM sessions WHERE started_at >= ? AND started_at < ?",
                        (day_start, day_end)).fetchone()
                    import datetime
                    date_str = datetime.datetime.fromtimestamp(day_start).strftime("%m-%d")
                    total = row["inp"] + row["outp"] + row["cr"] + row["cw"]
                    result.append({
                        "date": date_str,
                        "input": row["inp"], "output": row["outp"],
                        "cache": row["cr"] + row["cw"],
                        "total": total,
                        "sessions": row["cnt"],
                    })
        except Exception as e:
            result = {"error": str(e)}
        self._ok(json.dumps(result, ensure_ascii=False, default=str), "application/json")

    def _session_messages(self, session_id):
        params = parse_qs(urlparse(self.path).query)
        limit = int(params.get("limit", [50])[0])
        offset = int(params.get("offset", [0])[0])
        try:
            if _session_db:
                msgs = _session_db.get_messages_as_conversation(session_id, include_ancestors=False)
                # 分页：offset 从末尾往前数，limit 是每页条数
                start = -(limit + offset) if limit + offset < len(msgs) else 0
                end = -offset if offset > 0 else None
                msgs = msgs[start:end]
                # 精简字段：只保留前端需要的
                KEEP = {"role", "content"}
                msgs = [{k: m[k] for k in KEEP if k in m and m[k] is not None} for m in msgs]
            else:
                msgs = []
        except Exception as e:
            msgs = {"error": str(e)}
        self._ok(json.dumps(msgs, ensure_ascii=False, default=str), "application/json")

    def _rename_session(self, session_id):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length > 0 else {}
            title = body.get("title", "").strip()
            if not title:
                self._ok('{"error":"title required"}', "application/json")
                return
            if _session_db:
                _session_db.set_session_title(session_id, title)
            self._ok('{"ok":true}', "application/json")
        except Exception as e:
            self._ok(json.dumps({"error": str(e)}), "application/json")

    def _static(self):
        path = urlparse(self.path).path or "/"
        if path == "/":
            path = "/index.html"
        fp = os.path.normpath(os.path.join(STATIC_DIR, path.lstrip("/")))
        if not fp.startswith(os.path.normpath(STATIC_DIR)):
            return self.send_error(403)
        if os.path.isfile(fp):
            ext = os.path.splitext(fp)[1]
            self._ok(open(fp, "rb").read(), MIME.get(ext, "application/octet-stream"))
        else:
            # SPA fallback
            idx = os.path.join(STATIC_DIR, "index.html")
            if os.path.isfile(idx):
                self._ok(open(idx, "rb").read(), "text/html; charset=utf-8")
            else:
                self.send_error(404)

    def log_message(self, *a):
        pass  # 静默


class ThreadedServer(socketserver.ThreadingMixIn, HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = ThreadedServer(("0.0.0.0", port), Handler)
    print(f"Hermes Chat → http://localhost:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
