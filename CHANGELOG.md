# Changelog

## Unreleased

- New `feed.errors` module (exported from the package): `line_col(source,
  offset)` maps a byte offset to a 1-based (line, column) pair — the column
  is the 1-based BYTE offset within the line, no UTF-8 decoding — and
  `parse_error(msg, source, offset)` builds an `Error` reading
  `<msg> at line <L>, column <C>: '<snippet>'`, where the snippet is up to
  ~30 bytes of the offending line centered on the column,
  whitespace-trimmed, with `...` where truncated, and never multi-line.
  This is the error-reporting pattern shared with mojo-xml.
- Parse errors now carry that position + snippet wherever a byte offset
  exists at the raise site: every strict-mode XML error (previously a bare
  `(line L, column C)` suffix with no snippet), the structural XML errors
  both modes raise (unterminated constructs / start tags / attributes /
  attribute values, unquoted attribute values, malformed start/end tags,
  empty element names), every JSON Feed syntax error, and the positioned
  date-parsing errors (offsets relative to the date string).
- No mechanism change: parsers still `raise Error(...)`, no new error
  types, and existing `contains=`-style message checks keep matching.

## 0.1.0 — 2026-07-05

Initial release.

**Formats** — RSS 0.91/0.92, RSS 0.90/1.0 (RDF), RSS 2.0, Atom 1.0, and
JSON Feed 1.0/1.1, auto-detected. Podcast extensions (iTunes, Podcast
Index), Dublin Core, `content:encoded`, Media RSS, and Atom
`rel="enclosure"` enclosures. Namespaces resolved by URI, not literal
prefix.

**Model** — `Feed` / `FeedItem` with excerpt (`description`) and full
body (`content`) as separate fields; `item.date()` parses RFC 822 and
RFC 3339/ISO 8601 into a `FeedDate` with `unix_timestamp()`.

**Input** — `parse_feed` (strings), `parse_feed_bytes` (raw bytes with
encoding normalization: UTF-16 LE/BE, UTF-8 BOM, Latin-1/CP1252, lossy
U+FFFD recovery), and `fetch_feed(url)` via the system curl.

**Robustness** — liberal by default: unbalanced/crossed/stray tags are
recovered via an open-element stack, malformed entities pass through,
JSON nesting is depth-capped. `strict=True` flips recovery into
diagnostics with line/column locations for debugging feeds you produce
(`pixi run validate feed.xml`).

**Validation** — 70 tests; a 144-feed public corpus (all 138 fetchable
feeds parse); 5,400+ fuzz iterations with zero crashes or hangs;
131–146 MB/s compiled throughput.
