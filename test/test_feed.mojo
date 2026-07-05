from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from feed import (
    parse_feed,
    parse_feed_bytes,
    fetch_feed,
    Feed,
    KIND_RSS,
    KIND_ATOM,
    KIND_JSON,
)

comptime RSS_SAMPLE: StaticString = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Test Pod &amp; Friends</title>
    <link>https://example.com</link>
    <description>A test feed</description>
    <language>en</language>
    <item>
      <title>Episode One</title>
      <link>https://example.com/1</link>
      <description><![CDATA[Notes with <b>markup</b>]]></description>
      <pubDate>Mon, 09 Jun 2025 07:00:00 -0700</pubDate>
      <guid isPermaLink="false">ep-1</guid>
      <itunes:author>Host Name</itunes:author>
      <itunes:duration>3600</itunes:duration>
      <itunes:episode>1</itunes:episode>
      <enclosure url="https://example.com/1.mp3" length="1000" type="audio/mpeg"/>
    </item>
    <item>
      <title>Episode Two</title>
      <link>https://example.com/2</link>
      <description>Plain notes</description>
      <pubDate>Mon, 16 Jun 2025 07:00:00 -0700</pubDate>
      <guid>ep-2</guid>
    </item>
  </channel>
</rss>"""

comptime ATOM_SAMPLE: StaticString = """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Test</title>
  <subtitle>An atom feed</subtitle>
  <link href="https://example.org/"/>
  <entry>
    <title>First Post</title>
    <link rel="alternate" href="https://example.org/first"/>
    <id>urn:uuid:1</id>
    <published>2025-06-09T07:00:00Z</published>
    <updated>2025-06-10T07:00:00Z</updated>
    <summary>Hello world</summary>
  </entry>
</feed>"""


def test_rss_channel_fields() raises:
    var feed = parse_feed(String(RSS_SAMPLE))
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(feed.title, "Test Pod & Friends")
    assert_equal(feed.link, "https://example.com")
    assert_equal(feed.description, "A test feed")
    assert_equal(feed.language, "en")
    assert_equal(len(feed.items), 2)


def test_rss_item_fields() raises:
    var feed = parse_feed(String(RSS_SAMPLE))
    var item = feed.items[0].copy()
    assert_equal(item.title, "Episode One")
    assert_equal(item.link, "https://example.com/1")
    assert_equal(item.description, "Notes with <b>markup</b>")
    assert_equal(item.pub_date, "Mon, 09 Jun 2025 07:00:00 -0700")
    assert_equal(item.guid, "ep-1")
    assert_equal(item.author, "Host Name")
    assert_equal(item.duration, "3600")
    assert_equal(item.episode_number, "1")
    assert_equal(item.enclosure_url, "https://example.com/1.mp3")
    assert_equal(item.enclosure_type, "audio/mpeg")
    assert_equal(item.enclosure_length, "1000")


def test_rss_item_without_enclosure() raises:
    var feed = parse_feed(String(RSS_SAMPLE))
    var item = feed.items[1].copy()
    assert_equal(item.title, "Episode Two")
    assert_equal(item.enclosure_url, "")
    assert_equal(item.duration, "")


def test_atom_feed() raises:
    var feed = parse_feed(String(ATOM_SAMPLE))
    assert_equal(feed.kind, String(KIND_ATOM))
    assert_equal(feed.title, "Atom Test")
    assert_equal(feed.description, "An atom feed")
    assert_equal(feed.link, "https://example.org/")
    assert_equal(len(feed.items), 1)
    var item = feed.items[0].copy()
    assert_equal(item.title, "First Post")
    assert_equal(item.link, "https://example.org/first")
    assert_equal(item.guid, "urn:uuid:1")
    # <published> wins over <updated>
    assert_equal(item.pub_date, "2025-06-09T07:00:00Z")
    assert_equal(item.description, "Hello world")


def test_unbalanced_html_does_not_desync_items() raises:
    # A bare <br> (unescaped HTML void tag) must not corrupt nesting
    # tracking and swallow subsequent items.
    var source: String = """<rss version="2.0"><channel><title>T</title>
      <item><title>One</title><description>Line one<br>Line two</description><guid>g1</guid></item>
      <item><title>Two</title><description>Fine</description><guid>g2</guid></item>
    </channel></rss>"""
    var feed = parse_feed(source^)
    assert_equal(len(feed.items), 2)
    assert_equal(feed.items[0].title, "One")
    assert_equal(feed.items[0].description, "Line oneLine two")
    assert_equal(feed.items[1].title, "Two")
    assert_equal(feed.items[1].guid, "g2")


def test_stray_end_tag_ignored() raises:
    var source: String = """<rss version="2.0"><channel><title>T</title>
      <item><title>One</title></b></item>
    </channel></rss>"""
    var feed = parse_feed(source^)
    assert_equal(len(feed.items), 1)
    assert_equal(feed.items[0].title, "One")


def test_mixed_content_text_survives() raises:
    # Text before, inside, and after nested children must all be kept.
    var source: String = """<feed xmlns="http://www.w3.org/2005/Atom">
      <entry><summary>Hello <b>world</b> foo</summary></entry>
    </feed>"""
    var feed = parse_feed(source^)
    assert_equal(feed.items[0].description, "Hello world foo")


def test_atom_nested_author_name() raises:
    var source: String = """<feed xmlns="http://www.w3.org/2005/Atom">
      <entry><author><name>Jane Doe</name><email>jane@example.org</email></author></entry>
    </feed>"""
    var feed = parse_feed(source^)
    assert_equal(feed.items[0].author, "Jane Doe")


def test_atom_link_rel_enclosure() raises:
    var source: String = """<feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <link rel="alternate" href="https://example.org/ep1"/>
        <link rel="enclosure" href="https://example.org/ep1.mp3" type="audio/mpeg" length="1234"/>
      </entry>
    </feed>"""
    var feed = parse_feed(source^)
    var item = feed.items[0].copy()
    assert_equal(item.link, "https://example.org/ep1")
    assert_equal(item.enclosure_url, "https://example.org/ep1.mp3")
    assert_equal(item.enclosure_type, "audio/mpeg")
    assert_equal(item.enclosure_length, "1234")


def test_description_and_content_both_captured() raises:
    # WordPress/Substack shape: short excerpt first, full body second.
    var source: String = """<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
      <item>
        <description>Short excerpt</description>
        <content:encoded><![CDATA[<p>Full body</p>]]></content:encoded>
      </item>
    </channel></rss>"""
    var feed = parse_feed(source^)
    assert_equal(feed.items[0].description, "Short excerpt")
    assert_equal(feed.items[0].content, "<p>Full body</p>")


def test_atom_published_wins_regardless_of_order() raises:
    # <updated> is required in Atom and often appears first; <published>
    # must still win even when it closes later in the document.
    var source: String = """<feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <updated>2025-06-10T00:00:00Z</updated>
        <published>2025-06-09T00:00:00Z</published>
      </entry>
    </feed>"""
    var feed = parse_feed(source^)
    assert_equal(feed.items[0].pub_date, "2025-06-09T00:00:00Z")


def test_rss_1_0_rdf() raises:
    # RSS 1.0: rdf:RDF root, items are siblings of channel, dc:date,
    # identity in rdf:about, and an <image> sibling that must not
    # pollute channel fields.
    var source: String = """<?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns="http://purl.org/rss/1.0/"
             xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://example.org/">
        <title>RDF Feed</title>
        <link>https://example.org/</link>
        <description>An RSS 1.0 feed</description>
        <items><rdf:Seq><rdf:li resource="https://example.org/1"/></rdf:Seq></items>
      </channel>
      <image rdf:about="https://example.org/logo.png">
        <title>Logo Title Must Not Win</title>
        <link>https://example.org/logo-link</link>
      </image>
      <item rdf:about="https://example.org/1">
        <title>First</title>
        <link>https://example.org/1</link>
        <description>Body</description>
        <dc:creator>Jane</dc:creator>
        <dc:date>2025-01-02T03:04:05Z</dc:date>
      </item>
    </rdf:RDF>"""
    var feed = parse_feed(source^)
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(feed.title, "RDF Feed")
    assert_equal(feed.link, "https://example.org/")
    assert_equal(len(feed.items), 1)
    var item = feed.items[0].copy()
    assert_equal(item.title, "First")
    assert_equal(item.guid, "https://example.org/1")  # rdf:about
    assert_equal(item.pub_date, "2025-01-02T03:04:05Z")  # dc:date
    assert_equal(item.author, "Jane")


def test_rss_0_91() raises:
    var source: String = """<?xml version="1.0"?>
    <!DOCTYPE rss SYSTEM "http://my.netscape.com/publish/formats/rss-0.91.dtd">
    <rss version="0.91"><channel>
      <title>Old School</title>
      <link>https://example.org</link>
      <description>A 1999 feed</description>
      <item>
        <title>Hello</title>
        <link>https://example.org/hello</link>
        <description>World</description>
      </item>
    </channel></rss>"""
    var feed = parse_feed(source^)
    assert_equal(feed.title, "Old School")
    assert_equal(len(feed.items), 1)
    assert_equal(feed.items[0].title, "Hello")


def test_unsupported_root_raises() raises:
    with assert_raises():
        _ = parse_feed(String("<html><body/></html>"))


def test_namespace_resolution_nonstandard_prefix() raises:
    # iTunes tags bound to an unusual prefix must still map, because
    # resolution is by namespace URI, not by literal prefix.
    var source: String = """<rss version="2.0"
        xmlns:pod="http://www.itunes.com/dtds/podcast-1.0.dtd"
        xmlns:dublin="http://purl.org/dc/elements/1.1/"><channel>
      <item>
        <title>Ep</title>
        <pod:duration>1800</pod:duration>
        <pod:episode>7</pod:episode>
        <dublin:creator>Jane</dublin:creator>
      </item>
    </channel></rss>"""
    var feed = parse_feed(source^)
    var item = feed.items[0].copy()
    assert_equal(item.duration, "1800")
    assert_equal(item.episode_number, "7")
    assert_equal(item.author, "Jane")


def test_json_feed() raises:
    var source: String = """{
      "version": "https://jsonfeed.org/version/1.1",
      "title": "JSON Test",
      "home_page_url": "https://example.org/",
      "description": "A json feed",
      "author": {"name": "Top Author"},
      "items": [
        {
          "id": "1",
          "url": "https://example.org/1",
          "title": "First \\u0026 Foremost",
          "summary": "Short",
          "content_html": "<p>Full</p>",
          "date_published": "2026-07-01T10:00:00Z",
          "authors": [{"name": "Jane"}],
          "attachments": [
            {"url": "https://example.org/1.mp3", "mime_type": "audio/mpeg",
             "size_in_bytes": 1234, "duration_in_seconds": 900}
          ],
          "tags": ["a", "b"],
          "unknown_extension": {"nested": [1, 2, {"x": null}]}
        },
        {"id": "2", "external_url": "https://elsewhere.example", "title": "Second"}
      ]
    }"""
    var feed = parse_feed(source^)
    assert_equal(feed.kind, String(KIND_JSON))
    assert_equal(feed.title, "JSON Test")
    assert_equal(feed.link, "https://example.org/")
    assert_equal(len(feed.items), 2)
    var item = feed.items[0].copy()
    assert_equal(item.title, "First & Foremost")
    assert_equal(item.guid, "1")
    assert_equal(item.description, "Short")
    assert_equal(item.content, "<p>Full</p>")
    assert_equal(item.pub_date, "2026-07-01T10:00:00Z")
    assert_equal(item.author, "Jane")
    assert_equal(item.enclosure_url, "https://example.org/1.mp3")
    assert_equal(item.enclosure_type, "audio/mpeg")
    assert_equal(item.enclosure_length, "1234")
    assert_equal(item.duration, "900")
    # external_url fallback for link
    assert_equal(feed.items[1].link, "https://elsewhere.example")
    # date() works on RFC 3339 JSON Feed dates too
    assert_equal(item.date().year, 2026)


def test_parse_feed_bytes() raises:
    var doc: String = "<rss version='2.0'><channel><title>B</title><item><title>x</title></item></channel></rss>"
    var data = List[UInt8]()
    for b in doc.as_bytes():
        data.append(b)
    var feed = parse_feed_bytes(Span(data))
    assert_equal(feed.title, "B")
    assert_equal(len(feed.items), 1)


def test_json_deep_nesting_raises_cleanly() raises:
    # 10,000 nested arrays must raise, not overflow the stack.
    var hostile = String('{"title": ')
    for _ in range(10000):
        hostile += "["
    var source = hostile^
    with assert_raises(contains="nesting too deep"):
        _ = parse_feed(source^)


def test_fetch_feed_rejects_unsafe_urls() raises:
    with assert_raises(contains="http"):
        _ = fetch_feed("file:///etc/passwd")
    with assert_raises(contains="character"):
        _ = fetch_feed("https://example.org/'; rm -rf /'")
    with assert_raises(contains="character"):
        _ = fetch_feed("https://example.org/`id`")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
