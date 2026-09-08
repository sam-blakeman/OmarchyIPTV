#!/usr/bin/env python3
import gzip
import http.server
import importlib.machinery
import io
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sync = importlib.machinery.SourceFileLoader(
    "iptv_sync", str(ROOT / "bin" / "iptv-sync")
).load_module()


class ParseM3u(unittest.TestCase):
    def test_quoted_group_comma(self):
        text = '#EXTM3U\n#EXTINF:-1 tvg-id="bbc" group-title="UK, News",BBC One\nhttp://example/1\n'
        ch = sync.parse_m3u(text)
        self.assertEqual(len(ch), 1)
        self.assertEqual(ch[0]["name"], "BBC One")
        self.assertEqual(ch[0]["group"], "UK, News")
        self.assertTrue(ch[0]["id"].startswith("m3u-"))

    def test_stable_id(self):
        a = sync.stable_id("u", "n", "g")
        b = sync.stable_id("u", "n", "g")
        c = sync.stable_id("u", "n", "other")
        self.assertEqual(a, b)
        self.assertNotEqual(a, c)


class SlimAndMatch(unittest.TestCase):
    def test_slim_drops_url_and_logo(self):
        row = {"id": "xc-1", "name": "A", "logo": "http://l", "url": "http://s/secret", "group": "UK"}
        out = sync.slim(row)
        self.assertNotIn("url", out)
        self.assertNotIn("logo", out)
        self.assertEqual(out["name"], "A")

    def test_row_matches(self):
        row = {"name": "BBC One", "group": "UK"}
        self.assertTrue(sync.row_matches(row, "bbc", "UK"))
        self.assertFalse(sync.row_matches(row, "bbc", "US"))
        self.assertFalse(sync.row_matches(row, "itv", "UK"))

    def test_group_names(self):
        rows = [{"group": "UK"}, {"group": "UK"}, {"group": "US"}]
        self.assertEqual(sync.group_names(rows), ["All", "UK", "US"])


class Redact(unittest.TestCase):
    def test_redact_secret_and_urlencoded(self):
        sync.SECRETS[:] = ["p@ss"]
        self.assertEqual(sync.redact("pw=p@ss extra"), "pw=*** extra")
        sync.SECRETS[:] = []


class DumpVodGuard(unittest.TestCase):
    def test_all_without_query_is_empty(self):
        buf = tempfile.NamedTemporaryFile("w+", delete=False)
        try:
            old = sync.VOD_JSON
            sync.VOD_JSON = buf.name
            json.dump([{"id": "xcv-1", "name": "Film", "group": "Movies", "url": "http://x"}], buf)
            buf.close()
            import io
            from contextlib import redirect_stdout
            out = io.StringIO()
            with redirect_stdout(out):
                sync.dump_vod("", "All", 400)
            self.assertEqual(json.loads(out.getvalue()), [])
            sync.VOD_JSON = old
        finally:
            os.unlink(buf.name)


class BoundedReaderLimits(unittest.TestCase):
    MIB = 1 << 20

    def reader(self, payload, max_c=None, max_e=None):
        return sync.BoundedReader(io.BytesIO(payload), max_c or self.MIB, max_e or self.MIB, "test")

    def test_identity_passthrough(self):
        data = b"#EXTM3U\n#EXTINF:-1,One\nhttp://x/1\n" * 2000
        self.assertEqual(self.reader(data).read(), data)

    def test_identity_oversized_aborts(self):
        cap = 64 * 1024
        r = self.reader(b"x" * (cap + 1), max_c=cap, max_e=10 * cap)
        with self.assertRaises(sync.ResponseTooLarge):
            r.read()

    def test_gzip_roundtrip_and_partial_reads(self):
        data = b'{"stream_id": 1, "name": "abc"},' * 20000
        r = self.reader(gzip.compress(data))
        self.assertEqual(r.read(5), data[:5])
        self.assertEqual(r.read(), data[5:])

    def test_gzip_bomb_aborts_on_expanded_limit(self):
        bomb = gzip.compress(b"\0" * (32 * self.MIB))  # ~32 KiB on the wire
        self.assertLess(len(bomb), self.MIB)
        r = self.reader(bomb)
        with self.assertRaises(sync.ResponseTooLarge):
            r.read()
        # aborted incrementally: never inflated far past the cap
        self.assertLessEqual(r.n_out, self.MIB + sync.CHUNK)

    def test_truncated_gzip_is_an_error(self):
        gz = gzip.compress(b"abc" * 10000)
        with self.assertRaises(ValueError):
            self.reader(gz[:-20]).read()


class FetchOverHttp(unittest.TestCase):
    """fetch() end to end against a local server: the caps apply on the
    real urllib response object, not only on BytesIO."""

    @classmethod
    def setUpClass(cls):
        cls.bomb = gzip.compress(b"\0" * (8 << 20))
        cls.plain = b"#EXTM3U\n#EXTINF:-1,One\nhttp://x/1\n"
        bomb, plain = cls.bomb, cls.plain

        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = bomb if self.path == "/bomb" else plain
                self.send_response(200)
                if body is bomb:
                    self.send_header("Content-Encoding", "gzip")
                if self.path == "/huge":
                    self.send_header("Content-Length", str(10 << 30))
                else:
                    self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except OSError:
                    pass  # client hung up early, as it should for /huge

            def log_message(self, *a):
                pass

        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), H)
        cls.base = f"http://127.0.0.1:{cls.srv.server_port}"
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.old = sync.LIMITS["json"]
        sync.LIMITS["json"] = (1 << 20, 1 << 20)

    @classmethod
    def tearDownClass(cls):
        sync.LIMITS["json"] = cls.old
        cls.srv.shutdown()
        cls.srv.server_close()

    def test_small_body_ok(self):
        self.assertEqual(sync.fetch(self.base + "/ok", kind="json"), self.plain)

    def test_gzip_bomb_aborts(self):
        with self.assertRaises(sync.ResponseTooLarge):
            sync.fetch(self.base + "/bomb", kind="json")

    def test_declared_length_over_cap_aborts_before_reading(self):
        with self.assertRaises(sync.ResponseTooLarge):
            sync.fetch(self.base + "/huge", kind="json")


class ImportXmltv(unittest.TestCase):
    def test_streams_gzip_guide_into_db(self):
        now = int(time.time())

        def ts(t):
            return time.strftime("%Y%m%d%H%M%S", time.gmtime(t)) + " +0000"

        xml = ("<tv><channel id=\"c1\"><display-name>One</display-name></channel>"
               f"<programme start=\"{ts(now - 600)}\" stop=\"{ts(now + 600)}\" channel=\"c1\">"
               "<title>Now</title><desc>d</desc></programme>"
               f"<programme start=\"{ts(now + 3 * 86400)}\" stop=\"{ts(now + 3 * 86400 + 600)}\" "
               "channel=\"c1\"><title>Far</title></programme></tv>").encode()
        with tempfile.TemporaryDirectory() as d:
            old = sync.CACHE, sync.EPG_DB
            sync.CACHE, sync.EPG_DB = d, os.path.join(d, "epg.db")
            try:
                reader = sync.BoundedReader(io.BytesIO(gzip.compress(xml)), 1 << 20, 1 << 20)
                self.assertEqual(sync.import_xmltv(reader), 1)
                _now, by_ch = sync.epg_window()
                self.assertEqual([p["title"] for p in by_ch["c1"]], ["Now"])
                # bytes still accepted (and a bad guide keeps the previous EPG)
                with self.assertRaises(sync.ET.ParseError):
                    sync.import_xmltv(b"<tv><programme")
                _now, by_ch = sync.epg_window()
                self.assertEqual([p["title"] for p in by_ch["c1"]], ["Now"])
            finally:
                sync.CACHE, sync.EPG_DB = old


if __name__ == "__main__":
    unittest.main()
