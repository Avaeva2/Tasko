#!/usr/bin/env python3
"""Serve only the built student app on loopback, without stale demo caches."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=49182)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'build' / 'web'
if not (root / 'index.html').is_file():
    raise SystemExit('Сначала выполните flutter build web.')

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=str(root)))
print(f'Tasko Students: http://127.0.0.1:{args.port}', flush=True)
server.serve_forever()
