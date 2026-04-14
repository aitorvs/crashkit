#!/usr/bin/env python3
"""
Local Crashpad minidump ingestion server.

Accepts multipart POST uploads from Crashpad, saves .dmp files to ./dumps/,
and returns a CrashID so Crashpad marks the report as completed.

No third-party dependencies — stdlib only, works on Python 3.8+.

Usage:
    python3 crashpad_server.py             # default: port 8080
    python3 crashpad_server.py --port 9000
    python3 crashpad_server.py --dumps /tmp/dumps --port 8080

Upload endpoint:  POST /upload
Health check:     GET  /
Dump list:        GET  /dumps
"""

import argparse
import gzip
import json
import os
import socket
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


def parse_args():
    p = argparse.ArgumentParser(description="Local Crashpad minidump server")
    p.add_argument("--port", type=int, default=8080, help="Port to listen on (default: 8080)")
    p.add_argument("--dumps", default="dumps", help="Directory to save minidumps (default: ./dumps)")
    p.add_argument("--host", default="0.0.0.0", help="Host to bind to (default: 0.0.0.0)")
    return p.parse_args()


DUMPS_DIR = "dumps"  # overridden by args at startup


def parse_multipart(content_type: str, body: bytes) -> dict:
    """
    Parse a multipart/form-data body manually.
    Returns a dict of field_name -> bytes.
    """
    # Extract boundary from Content-Type header
    # e.g. "multipart/form-data; boundary=----WebKitFormBoundary..."
    boundary = None
    for token in content_type.split(";"):
        token = token.strip()
        if token.lower().startswith("boundary="):
            boundary = token[9:].strip().strip('"')
            break
    if not boundary:
        return {}

    delimiter = f"--{boundary}".encode()
    fields = {}

    # Split body on the delimiter
    parts = body.split(delimiter)
    for part in parts:
        # Skip preamble, epilogue, and final "--\r\n"
        if part in (b"", b"--", b"--\r\n", b"\r\n") or part.startswith(b"--"):
            continue
        # Each part: \r\n<headers>\r\n\r\n<body>\r\n
        if part.startswith(b"\r\n"):
            part = part[2:]  # strip leading \r\n
        if part.endswith(b"\r\n"):
            part = part[:-2]  # strip trailing \r\n

        # Split headers from body on the first blank line
        separator = b"\r\n\r\n"
        sep_idx = part.find(separator)
        if sep_idx == -1:
            continue
        headers_raw = part[:sep_idx].decode("utf-8", errors="replace")
        body_bytes = part[sep_idx + len(separator):]

        # Find the field name in Content-Disposition
        name = None
        for line in headers_raw.splitlines():
            if line.lower().startswith("content-disposition:"):
                for token in line.split(";"):
                    token = token.strip()
                    if token.lower().startswith("name="):
                        name = token[5:].strip().strip('"')
                        break
            if name:
                break

        if name is not None:
            fields[name] = body_bytes

    return fields


class CrashpadHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {fmt % args}")

    # ── GET / ──────────────────────────────────────────────────────────────────
    def do_GET(self):
        if self.path == "/":
            self._health()
        elif self.path == "/dumps":
            self._list_dumps()
        else:
            self._respond(404, "text/plain", b"Not found")

    def _health(self):
        dumps = self._dump_files()
        body = json.dumps({
            "status": "ok",
            "dumps_dir": os.path.abspath(DUMPS_DIR),
            "dump_count": len(dumps),
        }, indent=2).encode()
        self._respond(200, "application/json", body)

    def _list_dumps(self):
        entries = []
        for f in self._dump_files():
            path = os.path.join(DUMPS_DIR, f)
            stat = os.stat(path)
            meta_path = path.replace(".dmp", ".meta.json")
            meta = {}
            if os.path.exists(meta_path):
                with open(meta_path) as fh:
                    meta = json.load(fh)
            entries.append({
                "file": f,
                "size_kb": round(stat.st_size / 1024, 1),
                "received": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
                "annotations": meta.get("annotations", {}),
            })
        self._respond(200, "application/json", json.dumps(entries, indent=2).encode())

    # ── POST /upload ───────────────────────────────────────────────────────────
    def do_POST(self):
        path = self.path.split("?")[0]
        if path != "/upload":
            self._respond(404, "text/plain", b"Not found")
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self._respond(400, "text/plain", b"Expected multipart/form-data")
            return

        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            body = self._read_chunked()
        else:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)

        if self.headers.get("Content-Encoding", "").lower() == "gzip":
            try:
                body = gzip.decompress(body)
            except Exception as e:
                print(f"  ERROR decompressing gzip body: {e}")
                self._respond(400, "text/plain", b"Failed to decompress body")
                return

        try:
            fields = parse_multipart(content_type, body)
        except Exception as e:
            print(f"  ERROR parsing multipart: {e}")
            self._respond(400, "text/plain", b"Failed to parse multipart body")
            return

        if "upload_file_minidump" not in fields:
            print("  ERROR: no 'upload_file_minidump' field in upload")
            self._respond(400, "text/plain", b"Missing upload_file_minidump field")
            return

        dump_data = fields["upload_file_minidump"]

        # Everything else is annotations
        annotations = {
            k: v.decode("utf-8", errors="replace")
            for k, v in fields.items()
            if k != "upload_file_minidump"
        }

        # Save .dmp and sidecar .meta.json
        crash_id = str(uuid.uuid4())
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{timestamp}_{crash_id[:8]}.dmp"
        dump_path = os.path.join(DUMPS_DIR, filename)
        meta_path = dump_path.replace(".dmp", ".meta.json")

        os.makedirs(DUMPS_DIR, exist_ok=True)
        with open(dump_path, "wb") as f:
            f.write(dump_data)
        with open(meta_path, "w") as f:
            json.dump({
                "crash_id": crash_id,
                "received": datetime.now(tz=timezone.utc).isoformat(),
                "size_bytes": len(dump_data),
                "annotations": annotations,
            }, f, indent=2)

        print(f"  ✔ Saved {filename} ({len(dump_data) / 1024:.1f} KB)")
        for k, v in annotations.items():
            print(f"    {k}: {v}")

        # Crashpad expects "CrashID=<id>" to mark the upload as complete
        # and move the report from pending/ to completed/
        self._respond(200, "text/plain", f"CrashID={crash_id}".encode())

    # ── Helpers ────────────────────────────────────────────────────────────────
    def _read_chunked(self) -> bytes:
        """Read an HTTP chunked transfer-encoded body."""
        chunks = []
        while True:
            size_line = self.rfile.readline().strip()
            chunk_size = int(size_line, 16)
            if chunk_size == 0:
                break
            chunks.append(self.rfile.read(chunk_size))
            self.rfile.read(2)  # consume trailing \r\n after each chunk
        return b"".join(chunks)

    def _respond(self, status: int, content_type: str, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _dump_files(self):
        if not os.path.isdir(DUMPS_DIR):
            return []
        return sorted(f for f in os.listdir(DUMPS_DIR) if f.endswith(".dmp"))


def local_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "localhost"


def main():
    global DUMPS_DIR
    args = parse_args()
    DUMPS_DIR = args.dumps
    os.makedirs(DUMPS_DIR, exist_ok=True)

    server = HTTPServer((args.host, args.port), CrashpadHandler)

    ip = local_ip()
    print(f"Crashpad server listening on :{args.port}")
    print(f"  Dumps dir   : {os.path.abspath(DUMPS_DIR)}")
    print(f"  Upload URL  : http://{ip}:{args.port}/upload       ← real device")
    print(f"  Emulator URL: http://10.0.2.2:{args.port}/upload   ← Android emulator")
    print(f"  Health      : http://localhost:{args.port}/")
    print(f"  Dump list   : http://localhost:{args.port}/dumps")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
