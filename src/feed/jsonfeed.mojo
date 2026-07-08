"""JSON Feed (jsonfeed.org) parsing into the shared feed model.

A targeted recursive-descent parser: it decodes JSON syntax fully
(strings with escapes and surrogate pairs, numbers, nesting) but only
materializes the JSON Feed fields the model carries; everything else is
skipped structurally.
"""

from feed.errors import parse_error
from feed.model import Feed, FeedItem, KIND_JSON, _set_if_empty
from feed.xml_parser import _append_codepoint


comptime _MAX_JSON_DEPTH = 256


struct _Json(Movable):
    var bytes: List[UInt8]
    var pos: Int
    var depth: Int

    def __init__(out self, source: String):
        self.bytes = List[UInt8]()
        for b in source.as_bytes():
            self.bytes.append(b)
        self.pos = 0
        self.depth = 0

    def error(self, msg: String) -> Error:
        """A parse error positioned at the current cursor."""
        return self.error_at(msg, self.pos)

    def error_at(self, msg: String, p: Int) -> Error:
        """A parse error positioned at byte `p` of the JSON source."""
        return parse_error(
            "mojo-feed: invalid JSON Feed: " + msg, Span(self.bytes), p
        )

    def skip_ws(mut self):
        while self.pos < len(self.bytes):
            var b = self.bytes[self.pos]
            if b != 0x20 and b != 0x09 and b != 0x0A and b != 0x0D:
                break
            self.pos += 1

    def peek(self) -> UInt8:
        if self.pos >= len(self.bytes):
            return 0
        return self.bytes[self.pos]

    def expect(mut self, ch: String) raises:
        self.skip_ws()
        if self.pos >= len(self.bytes) or (
            self.bytes[self.pos] != ch.as_bytes()[0]
        ):
            raise self.error("expected '" + ch + "'")
        self.pos += 1

    def _hex4(mut self) raises -> Int:
        var v = 0
        for _ in range(4):
            if self.pos >= len(self.bytes):
                raise self.error("truncated \\u escape")
            var d = Int(self.bytes[self.pos])
            if d >= ord("0") and d <= ord("9"):
                v = v * 16 + (d - ord("0"))
            elif d >= ord("a") and d <= ord("f"):
                v = v * 16 + (d - ord("a") + 10)
            elif d >= ord("A") and d <= ord("F"):
                v = v * 16 + (d - ord("A") + 10)
            else:
                raise self.error("bad \\u escape")
            self.pos += 1
        return v

    def parse_string(mut self) raises -> String:
        self.expect('"')
        # Position of the opening quote — unterminated strings point
        # here, not at the useless end of input.
        var quote_pos = self.pos - 1
        var out = String()
        while True:
            if self.pos >= len(self.bytes):
                raise self.error_at("unterminated string", quote_pos)
            var b = self.bytes[self.pos]
            if b == UInt8(ord('"')):
                self.pos += 1
                return out^
            if b == UInt8(ord("\\")):
                self.pos += 1
                if self.pos >= len(self.bytes):
                    # Point at the backslash that started the escape.
                    raise self.error_at("truncated escape", self.pos - 1)
                var e = self.bytes[self.pos]
                self.pos += 1
                if e == UInt8(ord('"')):
                    out += '"'
                elif e == UInt8(ord("\\")):
                    out += "\\"
                elif e == UInt8(ord("/")):
                    out += "/"
                elif e == UInt8(ord("b")):
                    _append_codepoint(out, 8)
                elif e == UInt8(ord("f")):
                    _append_codepoint(out, 12)
                elif e == UInt8(ord("n")):
                    out += "\n"
                elif e == UInt8(ord("r")):
                    out += "\r"
                elif e == UInt8(ord("t")):
                    out += "\t"
                elif e == UInt8(ord("u")):
                    var cp = self._hex4()
                    if cp >= 0xD800 and cp <= 0xDBFF:
                        # Possible surrogate pair.
                        if (
                            self.pos + 1 < len(self.bytes)
                            and self.bytes[self.pos] == UInt8(ord("\\"))
                            and self.bytes[self.pos + 1] == UInt8(ord("u"))
                        ):
                            self.pos += 2
                            var low = self._hex4()
                            if low >= 0xDC00 and low <= 0xDFFF:
                                cp = (
                                    0x10000
                                    + ((cp - 0xD800) << 10)
                                    + (low - 0xDC00)
                                )
                            else:
                                _append_codepoint(out, 0xFFFD)
                                cp = low  # may itself be an unpaired low
                    _append_codepoint(out, cp)
                else:
                    # Point at the escape character itself.
                    raise self.error_at("unknown escape", self.pos - 1)
                continue
            # Raw byte (UTF-8 passes through untouched).
            var run_start = self.pos
            while self.pos < len(self.bytes):
                var c = self.bytes[self.pos]
                if c == UInt8(ord('"')) or c == UInt8(ord("\\")):
                    break
                self.pos += 1
            out += String(
                StringSlice(
                    unsafe_from_utf8=Span(self.bytes)[run_start : self.pos]
                )
            )

    def parse_number_raw(mut self) raises -> String:
        var start = self.pos
        while self.pos < len(self.bytes):
            var b = self.bytes[self.pos]
            if (
                (b >= UInt8(ord("0")) and b <= UInt8(ord("9")))
                or b == UInt8(ord("-"))
                or b == UInt8(ord("+"))
                or b == UInt8(ord("."))
                or b == UInt8(ord("e"))
                or b == UInt8(ord("E"))
            ):
                self.pos += 1
            else:
                break
        if self.pos == start:
            raise self.error("expected number")
        return String(
            StringSlice(unsafe_from_utf8=Span(self.bytes)[start : self.pos])
        )

    def _skip_literal(mut self, lit: String) raises:
        for b in lit.as_bytes():
            if self.pos >= len(self.bytes) or self.bytes[self.pos] != b:
                raise self.error("bad literal")
            self.pos += 1

    def skip_value(mut self) raises:
        # Recursion is bounded so hostile documents ("[[[[[…") raise
        # cleanly instead of overflowing the stack.
        self.depth += 1
        if self.depth > _MAX_JSON_DEPTH:
            raise self.error("nesting too deep")
        try:
            self._skip_value_inner()
        finally:
            self.depth -= 1

    def _skip_value_inner(mut self) raises:
        self.skip_ws()
        var b = self.peek()
        if b == UInt8(ord('"')):
            _ = self.parse_string()
        elif b == UInt8(ord("{")):
            self.pos += 1
            self.skip_ws()
            if self.peek() == UInt8(ord("}")):
                self.pos += 1
                return
            while True:
                _ = self.parse_string()
                self.expect(":")
                self.skip_value()
                self.skip_ws()
                if self.peek() == UInt8(ord(",")):
                    self.pos += 1
                    self.skip_ws()
                    continue
                self.expect("}")
                return
        elif b == UInt8(ord("[")):
            self.pos += 1
            self.skip_ws()
            if self.peek() == UInt8(ord("]")):
                self.pos += 1
                return
            while True:
                self.skip_value()
                self.skip_ws()
                if self.peek() == UInt8(ord(",")):
                    self.pos += 1
                    continue
                self.expect("]")
                return
        elif b == UInt8(ord("t")):
            self._skip_literal("true")
        elif b == UInt8(ord("f")):
            self._skip_literal("false")
        elif b == UInt8(ord("n")):
            self._skip_literal("null")
        else:
            _ = self.parse_number_raw()

    def parse_string_or_empty(mut self) raises -> String:
        """A string value; null becomes ""; other types are skipped."""
        self.skip_ws()
        if self.peek() == UInt8(ord('"')):
            return self.parse_string()
        self.skip_value()
        return String()


def _parse_author_name(mut j: _Json) raises -> String:
    """Author object: {"name": ..., "url": ...} → name."""
    j.skip_ws()
    if j.peek() != UInt8(ord("{")):
        j.skip_value()
        return String()
    var name = String()
    j.pos += 1
    j.skip_ws()
    if j.peek() == UInt8(ord("}")):
        j.pos += 1
        return name^
    while True:
        var key = j.parse_string()
        j.expect(":")
        if key == "name":
            name = j.parse_string_or_empty()
        else:
            j.skip_value()
        j.skip_ws()
        if j.peek() == UInt8(ord(",")):
            j.pos += 1
            j.skip_ws()
            continue
        j.expect("}")
        return name^


def _parse_item(mut j: _Json) raises -> FeedItem:
    var item = FeedItem()
    var external_url = String()
    j.expect("{")
    j.skip_ws()
    if j.peek() == UInt8(ord("}")):
        j.pos += 1
        return item^
    while True:
        var key = j.parse_string()
        j.expect(":")
        if key == "id":
            item.guid = j.parse_string_or_empty()
        elif key == "url":
            item.link = j.parse_string_or_empty()
        elif key == "external_url":
            external_url = j.parse_string_or_empty()
        elif key == "title":
            item.title = j.parse_string_or_empty()
        elif key == "content_html" or key == "content_text":
            _set_if_empty(item.content, j.parse_string_or_empty())
        elif key == "summary":
            item.description = j.parse_string_or_empty()
        elif key == "date_published":
            item.pub_date = j.parse_string_or_empty()
        elif key == "date_modified":
            _set_if_empty(item.pub_date, j.parse_string_or_empty())
        elif key == "author":
            _set_if_empty(item.author, _parse_author_name(j))
        elif key == "authors":
            # Array of author objects; first name wins.
            j.skip_ws()
            if j.peek() == UInt8(ord("[")):
                j.pos += 1
                j.skip_ws()
                if j.peek() == UInt8(ord("]")):
                    j.pos += 1
                else:
                    var first = True
                    while True:
                        if first:
                            _set_if_empty(item.author, _parse_author_name(j))
                            first = False
                        else:
                            j.skip_value()
                        j.skip_ws()
                        if j.peek() == UInt8(ord(",")):
                            j.pos += 1
                            j.skip_ws()
                            continue
                        j.expect("]")
                        break
            else:
                j.skip_value()
        elif key == "attachments":
            j.skip_ws()
            if j.peek() == UInt8(ord("[")):
                j.pos += 1
                j.skip_ws()
                if j.peek() == UInt8(ord("]")):
                    j.pos += 1
                else:
                    var first = True
                    while True:
                        if first:
                            _parse_attachment(j, item)
                            first = False
                        else:
                            j.skip_value()
                        j.skip_ws()
                        if j.peek() == UInt8(ord(",")):
                            j.pos += 1
                            j.skip_ws()
                            continue
                        j.expect("]")
                        break
            else:
                j.skip_value()
        else:
            j.skip_value()
        j.skip_ws()
        if j.peek() == UInt8(ord(",")):
            j.pos += 1
            j.skip_ws()
            continue
        j.expect("}")
        break
    if item.link.byte_length() == 0:
        item.link = external_url.copy()
    return item^


def _parse_attachment(mut j: _Json, mut item: FeedItem) raises:
    j.skip_ws()
    if j.peek() != UInt8(ord("{")):
        j.skip_value()
        return
    j.pos += 1
    j.skip_ws()
    if j.peek() == UInt8(ord("}")):
        j.pos += 1
        return
    while True:
        var key = j.parse_string()
        j.expect(":")
        if key == "url":
            item.enclosure_url = j.parse_string_or_empty()
        elif key == "mime_type":
            item.enclosure_type = j.parse_string_or_empty()
        elif key == "size_in_bytes":
            j.skip_ws()
            if j.peek() == UInt8(ord('"')):
                item.enclosure_length = j.parse_string()
            else:
                item.enclosure_length = j.parse_number_raw()
        elif key == "duration_in_seconds":
            j.skip_ws()
            if j.peek() == UInt8(ord('"')):
                item.duration = j.parse_string()
            else:
                item.duration = j.parse_number_raw()
        else:
            j.skip_value()
        j.skip_ws()
        if j.peek() == UInt8(ord(",")):
            j.pos += 1
            j.skip_ws()
            continue
        j.expect("}")
        return


def parse_json_feed(var source: String) raises -> Feed:
    """Parse a JSON Feed 1.0/1.1 document into a `Feed`."""
    var j = _Json(source)
    var feed = Feed()
    feed.kind = String(KIND_JSON)
    j.expect("{")
    j.skip_ws()
    if j.peek() == UInt8(ord("}")):
        j.pos += 1
        return feed^
    while True:
        var key = j.parse_string()
        j.expect(":")
        if key == "title":
            feed.title = j.parse_string_or_empty()
        elif key == "home_page_url":
            feed.link = j.parse_string_or_empty()
        elif key == "description":
            feed.description = j.parse_string_or_empty()
        elif key == "language":
            feed.language = j.parse_string_or_empty()
        elif key == "items":
            j.skip_ws()
            if j.peek() == UInt8(ord("[")):
                j.pos += 1
                j.skip_ws()
                if j.peek() == UInt8(ord("]")):
                    j.pos += 1
                else:
                    while True:
                        feed.items.append(_parse_item(j))
                        j.skip_ws()
                        if j.peek() == UInt8(ord(",")):
                            j.pos += 1
                            j.skip_ws()
                            continue
                        j.expect("]")
                        break
            else:
                j.skip_value()
        else:
            j.skip_value()
        j.skip_ws()
        if j.peek() == UInt8(ord(",")):
            j.pos += 1
            j.skip_ws()
            continue
        j.expect("}")
        break
    return feed^
