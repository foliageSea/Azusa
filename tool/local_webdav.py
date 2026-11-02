"""Loopback-only WebDAV fixture. Install tool/webdav-requirements.txt first."""

import argparse
import json
import tempfile
import threading
import time
from pathlib import Path

from cheroot.wsgi import Server
from wsgidav.wsgidav_app import WsgiDAVApp

from reset_webdav import create_fixture


class RequestLog:
    def __init__(self, app, path):
        self.app = app
        self.path = path
        self.lock = threading.Lock()
        self.active_writes = 0

    def __call__(self, environ, start_response):
        method = environ["REQUEST_METHOD"]
        writing = method in {"MOVE", "MKCOL", "PUT", "DELETE"}
        started = time.monotonic()
        status = "500"
        with self.lock:
            self.active_writes += int(writing)
            concurrent = self.active_writes

        def capture(value, headers, exc_info=None):
            nonlocal status
            status = value.split()[0]
            return start_response(value, headers, exc_info)

        try:
            response = self.app(environ, capture)
            try:
                yield from response
            finally:
                if hasattr(response, "close"):
                    response.close()
        finally:
            with self.lock:
                self.active_writes -= int(writing)
                with self.path.open("a", encoding="utf-8") as log:
                    log.write(json.dumps({
                        "method": method,
                        "path": environ.get("PATH_INFO"),
                        "status": int(status),
                        "concurrent_writes": concurrent if writing else None,
                        "elapsed_ms": round((time.monotonic() - started) * 1000, 2),
                    }, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    workspace = Path(tempfile.mkdtemp(prefix="azu-webdav-", dir="/tmp/opencode"))
    root = workspace / "share"
    create_fixture(root)
    config = {
        "provider_mapping": {"/dav": str(root)},
        "simple_dc": {"user_mapping": {"*": {"azu": {"password": "azu-local-test"}}}},
        "http_authenticator": {"accept_basic": True, "accept_digest": False, "default_to_digest": False},
        "fs_dav_provider": {"follow_symlinks": False},
        "verbose": 1,
        "logging": {"enable": False},
        "dir_browser": {"enable": True},
    }
    log = workspace / "requests.jsonl"
    app = RequestLog(WsgiDAVApp(config), log)
    server = Server(("127.0.0.1", args.port), app, numthreads=5)
    server.prepare()
    info = {"url": f"http://127.0.0.1:{server.bind_addr[1]}/dav/", "username": "azu",
            "password": "azu-local-test", "workspace": str(workspace), "request_log": str(log)}
    (workspace / "server.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(info, ensure_ascii=False), flush=True)
    try:
        server.serve()
    except KeyboardInterrupt:
        pass
    finally:
        server.stop()


if __name__ == "__main__":
    main()
