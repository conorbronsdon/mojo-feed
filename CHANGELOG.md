# Changelog

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
