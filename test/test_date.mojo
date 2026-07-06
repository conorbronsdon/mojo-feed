from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from feed import parse_date, parse_feed, FeedDate


def test_rfc822_with_numeric_offset() raises:
    var d = parse_date("Wed, 01 Jul 2026 03:30:00 -0700")
    assert_equal(d.year, 2026)
    assert_equal(d.month, 7)
    assert_equal(d.day, 1)
    assert_equal(d.hour, 3)
    assert_equal(d.minute, 30)
    assert_equal(d.tz_offset_minutes, -420)
    assert_equal(d.unix_timestamp(), 1782901800)


def test_rfc822_gmt_and_named_zones() raises:
    var gmt = parse_date("Sun, 05 Jul 2026 15:00:00 GMT")
    assert_equal(gmt.tz_offset_minutes, 0)
    var est = parse_date("Sun, 05 Jul 2026 15:00:00 EST")
    assert_equal(est.tz_offset_minutes, -300)
    # Same instant expressed in both zones differs by 5 hours.
    assert_equal(est.unix_timestamp() - gmt.unix_timestamp(), 5 * 3600)


def test_rfc822_without_weekday() raises:
    var d = parse_date("05 Jul 2026 15:00:00 +0000")
    assert_equal(d.day, 5)
    assert_equal(d.month, 7)


def test_rfc822_two_digit_year() raises:
    assert_equal(parse_date("05 Jul 99 00:00 GMT").year, 1999)
    assert_equal(parse_date("05 Jul 05 00:00 GMT").year, 2005)


def test_rfc3339_zulu() raises:
    var d = parse_date("2026-07-03T00:00:05Z")
    assert_equal(d.year, 2026)
    assert_equal(d.second, 5)
    assert_equal(d.tz_offset_minutes, 0)
    assert_equal(d.unix_timestamp(), 1783036805)


def test_rfc3339_offset_and_fraction() raises:
    var d = parse_date("2025-06-09T07:00:00.123+02:00")
    assert_equal(d.tz_offset_minutes, 120)
    var z = parse_date("2025-06-09T05:00:00Z")
    assert_equal(d.unix_timestamp(), z.unix_timestamp())


def test_rfc3339_date_only() raises:
    var d = parse_date("2026-07-03")
    assert_equal(d.hour, 0)
    assert_equal(d.tz_offset_minutes, 0)


def test_epoch() raises:
    assert_equal(parse_date("1970-01-01T00:00:00Z").unix_timestamp(), 0)
    assert_equal(
        parse_date("Thu, 01 Jan 1970 00:00:00 GMT").unix_timestamp(), 0
    )


def test_writable_roundtrip() raises:
    var d = parse_date("2026-07-03T01:02:03-07:00")
    assert_equal(String.write(d), "2026-07-03T01:02:03-07:00")


def test_item_date_method() raises:
    var source: String = """<rss version="2.0"><channel><item>
      <title>X</title><pubDate>Mon, 28 Oct 2024 00:00:00 +0000</pubDate>
    </item></channel></rss>"""
    var feed = parse_feed(source^)
    var d = feed.items[0].date()
    assert_equal(d.year, 2024)
    assert_equal(d.month, 10)
    assert_equal(d.day, 28)


def test_bad_dates_raise() raises:
    with assert_raises():
        _ = parse_date("")
    with assert_raises():
        _ = parse_date("not a date")
    with assert_raises():
        _ = parse_date("05 Zzz 2026 00:00 GMT")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
