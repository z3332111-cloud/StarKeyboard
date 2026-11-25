"""以本機 HTTP 伺服器測試實際下載 CLI（含真實 curl 重試）。

執行：python3 -m unittest discover -s tools/tests -p 'test_download_font.py' -v
不需第三方 Python 套件、不連外；504 重試測試約需 20 秒。
"""

from collections import Counter
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "download_font.py"
# 最小 SFNT 測試資料：一個表及四個位元組的內容，用來驗證傳輸完整性。
FONT = (struct.pack(">4sHHHH", b"\x00\x01\x00\x00", 1, 16, 0, 0)
        + struct.pack(">4sIII", b"name", 0, 28, 4) + b"test")
SHA256 = hashlib.sha256(FONT).hexdigest()


class DownloadFontTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.routes = {}
        cls.requests = Counter()

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                cls.requests[self.path] += 1
                responses = cls.routes.get(self.path, [(404, b"missing")])
                status, body = responses[min(cls.requests[self.path] - 1, len(responses) - 1)]
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.routes.clear()
        self.requests.clear()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.output = self.directory / "font.ttf"

    def run_download(self, *paths, sha256=None):
        # 與 workflow 相同的參數順序（OUTPUT、選項、URL）。
        command = [sys.executable, str(SCRIPT), str(self.output)]
        if sha256:
            command.extend(["--sha256", sha256])
        result = subprocess.run(command + [self.base + path for path in paths],
                                capture_output=True, text=True, timeout=45)
        return result

    def assert_success(self, result, content=FONT):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.output.read_bytes(), content)
        self.assertEqual(list(self.directory.iterdir()), [self.output])

    def test_transient_504_retries_same_source(self):
        self.routes["/retry"] = [(504, b"timeout"), (504, b"timeout"), (200, FONT)]
        self.assert_success(self.run_download("/retry", sha256=SHA256))
        self.assertEqual(self.requests["/retry"], 3)

    def test_exhausted_504_switches_source(self):
        self.routes["/release"] = [(504, b"timeout")]
        self.routes["/raw"] = [(200, FONT)]
        self.assert_success(self.run_download("/release", "/raw", sha256=SHA256))
        self.assertEqual(self.requests["/release"], 5)
        self.assertEqual(self.requests["/raw"], 1)

    def test_404_switches_source_without_retry(self):
        self.routes["/raw"] = [(200, FONT)]
        self.assert_success(self.run_download("/missing", "/raw"))
        self.assertEqual(self.requests["/missing"], 1)

    def test_html_and_truncated_font_are_rejected(self):
        for body in (b"<html>error</html>", FONT[:-1]):
            with self.subTest(body=body):
                self.routes["/bad"] = [(200, body)]
                self.routes["/good"] = [(200, FONT)]
                self.assert_success(self.run_download("/bad", "/good"))

    def test_checksum_mismatch_switches_source(self):
        self.routes["/wrong-version"] = [(200, FONT[:-4] + b"oops")]
        self.routes["/right-version"] = [(200, FONT)]
        self.assert_success(self.run_download("/wrong-version", "/right-version", sha256=SHA256))

    def test_all_sources_fail_without_leaving_output_or_partial_files(self):
        self.routes["/empty"] = [(200, b"")]
        result = self.run_download("/missing", "/empty")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("所有下載來源均失敗", result.stderr)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_failed_download_preserves_existing_file(self):
        self.output.write_bytes(FONT)
        self.assertNotEqual(self.run_download("/missing").returncode, 0)
        self.assertEqual(self.output.read_bytes(), FONT)
        self.assertEqual(list(self.directory.iterdir()), [self.output])

    def test_zip_font_download(self):
        self.output = self.directory / "font.zip"
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("fonts/example.ttf", FONT)
        self.routes["/bad"] = [(200, b"not a zip")]
        self.routes["/zip"] = [(200, data.getvalue())]
        self.assert_success(self.run_download("/bad", "/zip"), data.getvalue())


if __name__ == "__main__":
    unittest.main()
