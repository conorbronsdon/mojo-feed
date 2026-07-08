"""Structured feed dates without an external datetime dependency.

`parse_date` accepts the two formats feeds actually use — RFC 822/1123
(`Mon, 28 Oct 2024 07:30:00 -0700`, RSS `pubDate`) and RFC 3339/ISO 8601
(`2026-07-03T00:00:05+00:00`, Atom/JSON Feed) — and returns a `FeedDate`
carrying the civil fields, the UTC offset, and a Unix timestamp.
"""

from feed.errors import parse_error

comptime _MONTHS: StaticString = "janfebmaraprmayjunjulaugsepoctnovdec"


@fieldwise_init
struct FeedDate(Copyable, Equatable, Movable, Writable):
    """A parsed feed timestamp.

    Civil fields are as written in the document (not UTC-normalized);
    `tz_offset_minutes` holds the offset from UTC (+120 = UTC+2), and
    `unix_timestamp()` folds it in.
    """

    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int
    var tz_offset_minutes: Int

    def unix_timestamp(self) -> Int:
        """Seconds since the Unix epoch (folds in the UTC offset)."""
        # Days-from-civil (Howard Hinnant's algorithm).
        var y = self.year
        if self.month <= 2:
            y -= 1
        var era: Int
        if y >= 0:
            era = y // 400
        else:
            era = (y - 399) // 400
        var yoe = y - era * 400
        var mp = (self.month + 9) % 12
        var doy = (153 * mp + 2) // 5 + self.day - 1
        var doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
        var days = era * 146097 + doe - 719468
        return (
            days * 86400
            + self.hour * 3600
            + self.minute * 60
            + self.second
            - self.tz_offset_minutes * 60
        )

    def __eq__(self, other: Self) -> Bool:
        return (
            self.year == other.year
            and self.month == other.month
            and self.day == other.day
            and self.hour == other.hour
            and self.minute == other.minute
            and self.second == other.second
            and self.tz_offset_minutes == other.tz_offset_minutes
        )

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.year, "-")
        self._write_2d(writer, self.month)
        writer.write("-")
        self._write_2d(writer, self.day)
        writer.write("T")
        self._write_2d(writer, self.hour)
        writer.write(":")
        self._write_2d(writer, self.minute)
        writer.write(":")
        self._write_2d(writer, self.second)
        if self.tz_offset_minutes == 0:
            writer.write("Z")
        else:
            var off = self.tz_offset_minutes
            if off < 0:
                writer.write("-")
                off = -off
            else:
                writer.write("+")
            self._write_2d(writer, off // 60)
            writer.write(":")
            self._write_2d(writer, off % 60)

    @staticmethod
    def _write_2d(mut writer: Some[Writer], v: Int):
        if v < 10:
            writer.write("0")
        writer.write(v)


def _is_digit(b: UInt8) -> Bool:
    return b >= UInt8(ord("0")) and b <= UInt8(ord("9"))


def _to_lower(b: UInt8) -> UInt8:
    if b >= UInt8(ord("A")) and b <= UInt8(ord("Z")):
        return b + 32
    return b


struct _Cursor(Movable):
    var bytes: List[UInt8]
    var pos: Int

    def __init__(out self, s: String):
        self.bytes = List[UInt8]()
        for b in s.as_bytes():
            self.bytes.append(b)
        self.pos = 0

    def done(self) -> Bool:
        return self.pos >= len(self.bytes)

    def peek(self) -> UInt8:
        if self.done():
            return 0
        return self.bytes[self.pos]

    def skip_spaces(mut self):
        while not self.done() and (
            self.bytes[self.pos] == 0x20 or self.bytes[self.pos] == 0x09
        ):
            self.pos += 1

    def read_int(mut self, max_digits: Int) raises -> Int:
        var v = 0
        var n = 0
        while not self.done() and _is_digit(self.peek()) and n < max_digits:
            v = v * 10 + Int(self.peek()) - ord("0")
            self.pos += 1
            n += 1
        if n == 0:
            # Positions are relative to the (whitespace-trimmed) date
            # string being parsed, not the enclosing feed document.
            raise parse_error(
                "mojo-feed: expected digits in date",
                Span(self.bytes),
                self.pos,
            )
        return v

    def read_alpha_lower(mut self) -> String:
        var out = List[UInt8]()
        while not self.done():
            var b = self.peek()
            var lower = _to_lower(b)
            if lower < UInt8(ord("a")) or lower > UInt8(ord("z")):
                break
            out.append(lower)
            self.pos += 1
        return String(StringSlice(unsafe_from_utf8=Span(out)))


def _month_from_name(name: String) raises -> Int:
    if name.byte_length() < 3:
        raise Error("mojo-feed: bad month name in date: " + name)
    var prefix = String()
    var count = 0
    for cp in name.codepoint_slices():
        if count >= 3:
            break
        prefix += String(cp)
        count += 1
    var months = String(_MONTHS)
    var idx = months.find(prefix)
    if idx == -1 or idx % 3 != 0:
        raise Error("mojo-feed: bad month name in date: " + name)
    return idx // 3 + 1


def _zone_offset_minutes(zone: String) raises -> Int:
    """Offset for a named zone, per RFC 822's zone table."""
    if zone == "gmt" or zone == "ut" or zone == "utc" or zone == "z":
        return 0
    if zone == "est":
        return -5 * 60
    if zone == "edt":
        return -4 * 60
    if zone == "cst":
        return -6 * 60
    if zone == "cdt":
        return -5 * 60
    if zone == "mst":
        return -7 * 60
    if zone == "mdt":
        return -6 * 60
    if zone == "pst":
        return -8 * 60
    if zone == "pdt":
        return -7 * 60
    # Unknown alphabetic zones are treated as UTC (RFC 822 military
    # zones are ambiguous in practice; feedparser does the same).
    return 0


def _numeric_offset(mut cur: _Cursor) raises -> Int:
    var sign = 1
    if cur.peek() == UInt8(ord("-")):
        sign = -1
        cur.pos += 1
    elif cur.peek() == UInt8(ord("+")):
        cur.pos += 1
    var hours = cur.read_int(2)
    if cur.peek() == UInt8(ord(":")):
        cur.pos += 1
    var minutes = 0
    if _is_digit(cur.peek()):
        minutes = cur.read_int(2)
    return sign * (hours * 60 + minutes)


def _parse_rfc822(var cur: _Cursor) raises -> FeedDate:
    # Optional weekday: "Mon, "
    cur.skip_spaces()
    if not _is_digit(cur.peek()):
        _ = cur.read_alpha_lower()
        if cur.peek() == UInt8(ord(",")):
            cur.pos += 1
        cur.skip_spaces()
    var day = cur.read_int(2)
    cur.skip_spaces()
    var month = _month_from_name(cur.read_alpha_lower())
    cur.skip_spaces()
    var year = cur.read_int(4)
    if year < 100:
        # Two-digit years per RFC 2822 interpretation.
        if year >= 70:
            year += 1900
        else:
            year += 2000
    cur.skip_spaces()
    var hour = cur.read_int(2)
    var minute = 0
    var second = 0
    if cur.peek() == UInt8(ord(":")):
        cur.pos += 1
        minute = cur.read_int(2)
        if cur.peek() == UInt8(ord(":")):
            cur.pos += 1
            second = cur.read_int(2)
    cur.skip_spaces()
    var offset = 0
    if cur.peek() == UInt8(ord("+")) or cur.peek() == UInt8(ord("-")):
        offset = _numeric_offset(cur)
    elif not cur.done():
        var zone = cur.read_alpha_lower()
        if zone.byte_length() > 0:
            offset = _zone_offset_minutes(zone)
    return FeedDate(year, month, day, hour, minute, second, offset)


def _parse_rfc3339(var cur: _Cursor) raises -> FeedDate:
    var year = cur.read_int(4)
    if cur.peek() != UInt8(ord("-")):
        raise parse_error("mojo-feed: bad ISO date", Span(cur.bytes), cur.pos)
    cur.pos += 1
    var month = cur.read_int(2)
    if cur.peek() != UInt8(ord("-")):
        raise parse_error("mojo-feed: bad ISO date", Span(cur.bytes), cur.pos)
    cur.pos += 1
    var day = cur.read_int(2)
    var hour = 0
    var minute = 0
    var second = 0
    var offset = 0
    var sep = cur.peek()
    if sep == UInt8(ord("T")) or sep == UInt8(ord("t")) or sep == 0x20:
        cur.pos += 1
        hour = cur.read_int(2)
        if cur.peek() == UInt8(ord(":")):
            cur.pos += 1
            minute = cur.read_int(2)
        if cur.peek() == UInt8(ord(":")):
            cur.pos += 1
            second = cur.read_int(2)
        if cur.peek() == UInt8(ord(".")):
            cur.pos += 1
            _ = cur.read_int(9)  # fractional seconds: parsed, dropped
        var z = cur.peek()
        if z == UInt8(ord("Z")) or z == UInt8(ord("z")):
            cur.pos += 1
        elif z == UInt8(ord("+")) or z == UInt8(ord("-")):
            offset = _numeric_offset(cur)
    return FeedDate(year, month, day, hour, minute, second, offset)


def parse_date(raw: String) raises -> FeedDate:
    """Parse an RFC 822 (RSS) or RFC 3339/ISO 8601 (Atom) date string."""
    var trimmed = String(StringSlice(raw).strip())
    if trimmed.byte_length() == 0:
        raise Error("mojo-feed: empty date")
    var cur = _Cursor(trimmed)
    # RFC 3339 starts with a 4-digit year followed by '-'.
    var bytes = trimmed.as_bytes()
    if (
        len(bytes) >= 5
        and _is_digit(bytes[0])
        and _is_digit(bytes[1])
        and _is_digit(bytes[2])
        and _is_digit(bytes[3])
        and bytes[4] == UInt8(ord("-"))
    ):
        return _parse_rfc3339(cur^)
    return _parse_rfc822(cur^)
