"""Integration tests against real-world feed snapshots:

- cot_feed.xml      Transistor podcast RSS (~547 KB, 66 episodes, CDATA,
                    itunes/podcast namespaces, stylesheet PI)
- rss_substack.xml  Substack RSS (~811 KB single line, CDATA channel
                    title, content:encoded, dc:creator, image enclosures)
- rss_hn.xml        Hacker News front page RSS (escaped-HTML descriptions)
- atom_xkcd.xml     xkcd Atom (rel="alternate" links, <updated> only)
"""

from std.testing import assert_equal, assert_true, TestSuite

from feed import parse_feed, KIND_RSS, KIND_ATOM, KIND_JSON


def _load_fixture() raises -> String:
    return open("test/data/cot_feed.xml", "r").read()


def test_parses_real_transistor_feed() raises:
    var feed = parse_feed(_load_fixture())
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(
        feed.title, "Chain of Thought | AI Agents, Infrastructure & Engineering"
    )
    assert_equal(len(feed.items), 66)


def test_every_item_has_core_fields() raises:
    var feed = parse_feed(_load_fixture())
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.guid.byte_length() > 0)
        assert_true(item.pub_date.byte_length() > 0)
        assert_true(item.enclosure_url.byte_length() > 0)
        assert_equal(item.enclosure_type, "audio/mpeg")


def test_substack_feed() raises:
    var feed = parse_feed(open("test/data/rss_substack.xml", "r").read())
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(feed.title, "Dev Interrupted")  # CDATA channel title
    assert_equal(len(feed.items), 20)
    var item = feed.items[0].copy()
    assert_true(item.title.byte_length() > 0)
    assert_true(item.author.byte_length() > 0)  # dc:creator
    assert_true(item.link.byte_length() > 0)


def test_hacker_news_feed() raises:
    var feed = parse_feed(open("test/data/rss_hn.xml", "r").read())
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(feed.title, "Hacker News: Front Page")
    assert_equal(len(feed.items), 20)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)
        assert_true(item.pub_date.byte_length() > 0)


def test_xkcd_atom_feed() raises:
    var feed = parse_feed(open("test/data/atom_xkcd.xml", "r").read())
    assert_equal(feed.kind, String(KIND_ATOM))
    assert_equal(feed.title, "xkcd.com")
    assert_equal(feed.link, "https://xkcd.com/")
    assert_equal(len(feed.items), 4)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)  # from href attribute
        assert_true(item.guid.byte_length() > 0)
        assert_true(item.pub_date.byte_length() > 0)  # <updated> fallback


def test_youtube_atom_feed() raises:
    var feed = parse_feed(open("test/data/atom_youtube.xml", "r").read())
    assert_equal(feed.kind, String(KIND_ATOM))
    assert_equal(feed.title, "Google for Developers")
    assert_equal(len(feed.items), 15)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)
        assert_true(item.pub_date.byte_length() > 0)
        assert_true(item.enclosure_url.byte_length() > 0)  # media:content
        assert_true(item.author.byte_length() > 0)  # <author><name>
        assert_true(item.description.byte_length() > 0)  # media:description


def test_wordpress_feed() raises:
    var feed = parse_feed(open("test/data/rss_wordpress.xml", "r").read())
    assert_equal(feed.kind, String(KIND_RSS))
    assert_equal(feed.title, "TechCrunch")
    assert_equal(len(feed.items), 20)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)
        assert_true(item.author.byte_length() > 0)  # dc:creator


def test_slashdot_rdf_feed() raises:
    # RSS 1.0 (RDF root, items as channel siblings) declared ISO-8859-1 —
    # exercises both the RDF path and encoding transcoding.
    var feed = parse_feed(open("test/data/rdf_slashdot.xml", "r").read())
    assert_equal(feed.kind, String(KIND_RSS))
    assert_true(feed.title.byte_length() > 0)
    assert_true(len(feed.items) >= 10)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)
        assert_true(item.pub_date.byte_length() > 0)  # dc:date


def test_real_json_feed() raises:
    var feed = parse_feed(
        open("test/data/jsonfeed_recompiled.json", "r").read()
    )
    assert_equal(feed.kind, String(KIND_JSON))
    assert_equal(feed.title, "Recompiled")
    assert_true(len(feed.items) >= 5)
    for item in feed.items:
        assert_true(item.title.byte_length() > 0)
        assert_true(item.guid.byte_length() > 0)
        assert_true(item.link.byte_length() > 0)


def test_dates_parse_across_all_fixtures() raises:
    # Every pub_date in every fixture must be machine-parseable and
    # produce a sane timestamp (2000..2036).
    var paths = [
        String("test/data/cot_feed.xml"),
        String("test/data/rss_substack.xml"),
        String("test/data/rss_hn.xml"),
        String("test/data/atom_xkcd.xml"),
        String("test/data/atom_youtube.xml"),
        String("test/data/rss_wordpress.xml"),
        String("test/data/rdf_slashdot.xml"),
        String("test/data/jsonfeed_recompiled.json"),
    ]
    for path in paths:
        var feed = parse_feed(open(path, "r").read())
        for item in feed.items:
            if item.pub_date.byte_length() == 0:
                continue
            var ts = item.date().unix_timestamp()
            assert_true(ts > 946684800, msg=String(path))  # 2000-01-01
            assert_true(ts < 2082758400, msg=String(path))  # 2036-01-01


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
