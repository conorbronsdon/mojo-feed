"""The parsed-feed data model shared by the XML and JSON Feed parsers."""

from feed.date import FeedDate, parse_date

comptime KIND_RSS = "rss"
comptime KIND_ATOM = "atom"
comptime KIND_JSON = "json"


def _stripped(text: String) -> String:
    return String(StringSlice(text).strip())


def _set_if_empty(mut field: String, value: String):
    if field.byte_length() == 0:
        field = value.copy()


struct FeedItem(Copyable, Movable, Writable):
    """One episode / article. Empty string means the field was absent.

    `description` holds the excerpt (`<description>`/`<summary>`);
    `content` holds the full body (`<content:encoded>`/`<content>`)
    when the feed provides both.
    """

    var title: String
    var link: String
    var description: String
    var content: String
    var pub_date: String
    var guid: String
    var author: String
    var enclosure_url: String
    var enclosure_type: String
    var enclosure_length: String
    var duration: String
    var episode_number: String

    def __init__(out self):
        self.title = String()
        self.link = String()
        self.description = String()
        self.content = String()
        self.pub_date = String()
        self.guid = String()
        self.author = String()
        self.enclosure_url = String()
        self.enclosure_type = String()
        self.enclosure_length = String()
        self.duration = String()
        self.episode_number = String()

    def date(self) raises -> FeedDate:
        """`pub_date` parsed into a structured date (raises if absent
        or unparseable)."""
        return parse_date(self.pub_date)

    def write_to(self, mut writer: Some[Writer]):
        writer.write("FeedItem(", self.title, " @ ", self.pub_date, ")")


struct Feed(Copyable, Movable, Writable):
    """A parsed feed: channel-level metadata plus items."""

    var kind: String  # KIND_RSS, KIND_ATOM, or KIND_JSON
    var title: String
    var link: String
    var description: String
    var language: String
    var items: List[FeedItem]

    def __init__(out self):
        self.kind = String()
        self.title = String()
        self.link = String()
        self.description = String()
        self.language = String()
        self.items = List[FeedItem]()

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "Feed(",
            self.kind,
            ": ",
            self.title,
            ", ",
            len(self.items),
            " items)",
        )
