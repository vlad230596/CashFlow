from __future__ import annotations

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


CSP = (
    "default-src 'self'; connect-src 'self'; img-src 'self' data: blob:; "
    "font-src 'self' data:; style-src 'self' 'unsafe-inline'; "
    "script-src 'self' 'wasm-unsafe-eval'; worker-src 'self' blob:; "
    "manifest-src 'self'; frame-ancestors 'none'; base-uri 'self'; "
    "form-action 'self'"
)


class SpaHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        path = Path(self.translate_path(self.path))
        if not path.exists() and not path.suffix:
            self.path = '/index.html'
        return super().send_head()

    def end_headers(self) -> None:
        self.send_header('Content-Security-Policy', CSP)
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--port', type=int, required=True)
    args = parser.parse_args()
    handler = lambda *handler_args, **handler_kwargs: SpaHandler(  # noqa: E731
        *handler_args,
        directory=str(args.directory.resolve()),
        **handler_kwargs,
    )
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()


if __name__ == '__main__':
    main()

