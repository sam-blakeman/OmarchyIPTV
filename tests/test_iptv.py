#!/usr/bin/env python3
import importlib.machinery
import json
import os
import tempfile
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


if __name__ == "__main__":
    unittest.main()
