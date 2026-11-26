"""Simulator-only OAuth callback bridge for the Supabase localhost fallback.

Supabase redirects to the configured Site URL when an app deep link is not yet
present in its redirect allow-list. During local iOS Simulator development that
URL is http://localhost:3000. This page forwards the URL fragment (which holds
the Supabase session) to Mockexa's registered custom URL scheme.

Production builds must still allow ``mockexa://auth/callback`` in Supabase.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


CALLBACK_PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Returning to Mockexa</title>
  <style>
    body { font: 17px -apple-system, BlinkMacSystemFont, sans-serif; color: #0b1930;
           display: grid; min-height: 100vh; place-items: center; margin: 0; }
    main { max-width: 28rem; padding: 2rem; text-align: center; }
  </style>
</head>
<body>
  <main><h1>Returning to Mockexa…</h1><p>You can close this window after the app opens.</p></main>
  <script>
    const suffix = window.location.hash || window.location.search;
    window.location.replace('mockexa://auth/callback' + suffix);
  </script>
</body>
</html>""".encode("utf-8")


class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(CALLBACK_PAGE)))
        self.end_headers()
        self.wfile.write(CALLBACK_PAGE)

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    print("Mockexa OAuth callback bridge listening on http://localhost:3000")
    ThreadingHTTPServer(("127.0.0.1", 3000), CallbackHandler).serve_forever()
