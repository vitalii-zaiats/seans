"""kinoukr.tv — the listing pages, and the page behind each card.

Each listing entry looks like:

    <div class="short clearfix with-mask">
      <div class="short-img img-box">
        <img src="/uploads/mini/short/..." alt="Title">
      </div>
      <div class="short-text">
        <a class="short-title" href="https://kinoukr.tv/9136-marave.html">Title</a>
      </div>
    </div>

That card carries a thumbnail and a name; everything else lives on the film page
it links to. Series share the same template, so `parse_movie` reads both:

    <article class="full">
      <div class="ftitle"><h1>Мараве</h1><div class="foriginal">Marave</div></div>
      <div class="fposter">
        <a href="/uploads/posts/2026-07/948acc76a8_posterx.webp">   <- full-size
          <img src="/uploads/mini/short/...jpg">                    <- the card's
        <div class="m-meta m-qual">HD 1080p</div>
        <div class="m-meta m-imdb" title="110 голосів">3.9</div>
      <div class="finfo">
        <div class="sd-line"><span>Рік:</span><a>2026</a></div>      <- label, value
        ...
      <div itemprop="description">...</div>
      <div class="fplayer">                                         <- one iframe
        <div class="tabs-sel"><span>Онлайн</span><span>Трейлер</span>   per tab
        <div class="tabs-b"><iframe src="https://ashdi.vip/vod/273324">
        <div class="tabs-b"><iframe src="https://www.youtube.com/embed/...">
"""

import re
from typing import Any, TypedDict, cast
from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag

from crawlers.models import Item
from crawlers.source import Source, register

BASE = "https://kinoukr.tv/"
CARD_SELECTOR = "div.short.clearfix.with-mask"

# What a genre link points at is what tells a film from a series: the page's own
# schema.org type is Movie either way, and the breadcrumb sometimes disagrees
# with the section the genres and the player belong to.
KINDS = {
    "filmss": "film",
    "series": "series",
    "cartoonss": "cartoon",
    "cartoon-seriess": "cartoon-series",
    # A section of its own on this site, the way cartoons are.
    "anime": "anime",
}

# Genres come out of the links, not their text: the site names them in English
# in the URL — `/filmss/action/`, `/series/s-drama/` — and that name is stable
# while the visible one is Ukrainian. Callers get a key; whoever renders it is
# the one who knows what language the reader wants.
#
# Only the slugs whose spelling isn't what the genre is called in English are
# listed; everything else passes through as it is.
GENRES = {
    "fantastic": "sci-fi",
    "military": "war",
    "mystic": "mystery",
    "korotkometrazhni": "short",
}

# The other two link families a `finfo` row can hold: a search by year or country,
# and the site's own themed collections. Neither is a genre.
NOT_GENRES = frozenset({"xfsearch", "collection"})

# The `finfo` rows worth keeping, by label. What's left out is navigation rather
# than fact: "В списках" is this page's rank in a dozen best-of listings.
LINES = {
    "Рік": "year",
    "Жанр": "genres",
    "Країна": "countries",
    "Кінокомпанія": "studio",
    "Канал": "channel",
    "Режисер": "directors",
    "В ролях": "cast",
    "Звук": "audio",
    "Тривалість": "duration",
    "Вік": "age",
    "Прем'єра (UA)": "premiere",
    "Статус": "status",
    "В збірках": "collections",
}

# Rows read as several values; every other row is one string.
LISTED = frozenset({"genres", "countries", "directors", "cast", "collections"})

MOVIE_ID_RE = re.compile(r"/(\d+)-[^/]*\.html$")
# A film says `2026`; a series says how long it ran: `2007 — 2010`.
YEAR_RE = re.compile(r"(\d{4})(?:\s*[-–—]\s*(\d{4}))?")


class Movie(TypedDict, total=False):
    """What the film page adds, flat in `Item.extra`.

    Every key is optional, because the pages differ: an announcement has no
    player, a film has no season status, a documentary has no cast.
    """

    id: int  # the site's own numeric id, out of the URL
    kind: str  # film | series | cartoon | cartoon-series
    original_title: str  # the title as released, when it isn't Ukrainian
    year: int
    year_end: int  # only for a series, and only once it has stopped running
    quality: str  # "HD 1080p", or "Анонс" while there's nothing to watch yet
    imdb: float
    imdb_votes: int
    rating: float  # the site's own score, and how many votes it stands on
    votes: int
    genres: list[str]
    countries: list[str]
    studio: str
    channel: str  # for series that aired on one
    directors: list[str]
    cast: list[str]
    audio: str  # studio and dub type in one line: "Postmodern | Професійний..."
    duration: str  # "01:32:40" for a film, "44 – 64 хв" for a series
    age: str
    premiere: str
    status: str  # "1 сезон (8 серій з 8)"
    collections: list[str]
    description: str
    players: list[str]  # embed URLs in tab order — ashdi.vip, tortuga.tw
    trailer: str


@register
class Kinoukr(Source):
    name = "kinoukr"
    # Everything this site publishes is dubbed into Ukrainian.
    language = "uk"
    # Every card links to a film page, and that page is where the data is.
    item_pages = True

    def page_url(self, number: int) -> str:
        return urljoin(BASE, f"page/{number}/")

    def parse(self, html: str) -> list[Item]:
        soup = BeautifulSoup(html, "lxml")
        items = []

        for card in soup.select(CARD_SELECTOR):
            link = card.select_one("a.short-title")
            if link is None or not link.get("href"):
                continue

            image = card.select_one(".short-img img")
            poster = image.get("src") if image else None
            # `alt` comes back as a list for the attributes HTML defines as
            # multi-valued. This one is not, but the type cannot know that.
            alt = image.get("alt", "") if image else ""
            title = link.get_text(strip=True) or (alt if isinstance(alt, str) else "")

            items.append(
                Item(
                    title=title,
                    # Resolve against BASE, not the response URL: page 1 redirects
                    # to http://kinoukr.tv/home/ and would drag links back to http.
                    url=urljoin(BASE, str(link["href"])),
                    poster=urljoin(BASE, str(poster)) if poster else None,
                )
            )

        return items

    def parse_item(self, html: str, url: str) -> Item | None:
        """The page behind a card — what the engines fetch for `--details`."""
        return parse_movie(html, url)


def parse_movie(html: str, url: str = "") -> Item | None:
    """A film page as an Item, with everything the page adds in `extra`.

    The poster is the page's own full-size one rather than the listing thumbnail
    — same image, several times the resolution. `url` is only a fallback for the
    page's canonical link, which every film page carries.

    None means the HTML isn't a film page: a 404, or a section index.
    """
    soup = BeautifulSoup(html, "lxml")
    article = soup.select_one("article.full")
    if article is None:
        return None

    canonical = soup.select_one("link[rel=canonical][href]")
    page_url = urljoin(BASE, str(canonical["href"])) if canonical else url

    extra: dict[str, Any] = {}
    if movie_id := MOVIE_ID_RE.search(page_url):
        extra["id"] = int(movie_id[1])

    extra.update(_info(soup))
    extra.update(_ratings(soup))

    if kind := KINDS.get(_section(soup)):
        extra["kind"] = kind
    if original := soup.select_one(".foriginal"):
        extra["original_title"] = original.get_text(strip=True)
    if quality := soup.select_one(".fposter .m-qual"):
        extra["quality"] = quality.get_text(strip=True)
    if description := soup.select_one("[itemprop=description]"):
        extra["description"] = _paragraphs(description)

    players, trailer = _players(soup)
    if players:
        extra["players"] = players
    if trailer:
        extra["trailer"] = trailer

    return Item(
        title=_title(soup),
        url=page_url,
        poster=_poster(soup),
        # Flat by design — `Item.to_dict` merges extras beside title and url.
        extra=cast(Movie, extra),
    )


def _title(soup: BeautifulSoup) -> str:
    heading = soup.select_one(".ftitle h1")
    if heading:
        return heading.get_text(strip=True)
    # og:title is the SEO sentence ("Фільм X 2026 дивитись онлайн..."), so it's a
    # last resort rather than an equal alternative.
    meta = soup.select_one('meta[property="og:title"][content]')
    return str(meta["content"]).strip() if meta else ""


def _poster(soup: BeautifulSoup) -> str | None:
    """The full-size poster the page links to, not the thumbnail it displays."""
    link = soup.select_one(".fposter a[href]")
    if link:
        return urljoin(BASE, str(link["href"]))
    meta = soup.select_one('meta[property="og:image"][content]')
    if meta:
        return urljoin(BASE, str(meta["content"]))
    image = soup.select_one(".fposter img[src]")
    return urljoin(BASE, str(image["src"])) if image else None


def _section(soup: BeautifulSoup) -> str:
    """The site section this page belongs to, read off its genre links."""
    for link in soup.select(".finfo .sd-line a[href]"):
        path = urljoin(BASE, str(link["href"])).removeprefix(BASE)
        head = path.split("/", 1)[0]
        if head in KINDS:
            return head
    return ""


def _info(soup: BeautifulSoup) -> dict[str, Any]:
    """The `finfo` table: one labelled row at a time, unknown labels dropped."""
    info: dict[str, Any] = {}

    for line in soup.select(".finfo .sd-line"):
        label = line.find("span")
        if label is None:
            continue

        key = LINES.get(label.get_text(strip=True).rstrip(":"))
        if key is None:
            continue

        value = line.get_text(" ", strip=True).removeprefix(label.get_text(strip=True))
        value = value.strip()
        if not value:
            continue

        if key == "genres":
            # Ukrainian names only survive when a row somehow carries no links,
            # and a row that says "---" says nothing at all.
            genres = _genres(line) or [
                name for name in _many(line, value) if any(char.isalnum() for char in name)
            ]
            if genres:
                info[key] = genres
        elif key in LISTED:
            info[key] = _many(line, value)
        elif key == "year":
            info.update(_years(value))
        else:
            info[key] = value

    return info


def _years(value: str) -> dict[str, int]:
    """`2026` for a film, `2007 — 2010` for a series that has finished running."""
    match = YEAR_RE.search(value)
    if match is None:
        return {}

    years = {"year": int(match[1])}
    if match[2]:
        years["year_end"] = int(match[2])
    return years


def _genres(line: Tag) -> list[str]:
    """Genre keys, read off each link's own path.

    `/filmss/action/` and `/series/s-action/` are the same genre said twice, so
    the section and its `s-` prefix both come off. Some genres are a section of
    their own — `/anime/`, `/adult/` — and a cartoon page links its section and
    nothing finer, so a lone section stands for the genre it names.
    """
    genres = []

    for link in line.select("a[href]"):
        parts = [
            part
            for part in urljoin(BASE, str(link["href"])).removeprefix(BASE).strip("/").split("/")
            if part
        ]
        if not parts or parts[0] in NOT_GENRES:
            continue

        slug = (parts[1] if len(parts) > 1 else KINDS.get(parts[0], parts[0])).removeprefix("s-")
        genres.append(GENRES.get(slug, slug))

    return list(dict.fromkeys(genres))


def _many(line: Tag, value: str) -> list[str]:
    """A row's values. Linked ones come as links; the rest are comma-separated."""
    parts = [link.get_text(strip=True) for link in line.select("a")] or value.split(",")
    return [part.strip(" ,") for part in parts if part.strip(" ,")]


def _ratings(soup: BeautifulSoup) -> dict[str, Any]:
    """IMDB's score off the poster badge, the site's own out of its microdata."""
    ratings: dict[str, Any] = {}

    if imdb := soup.select_one(".fposter .m-imdb"):
        if score := _number(imdb.get_text(strip=True)):
            ratings["imdb"] = score
        # The badge's tooltip is where the vote count is: "110 голосів".
        if votes := re.sub(r"\D", "", str(imdb.get("title") or "")):
            ratings["imdb_votes"] = int(votes)

    for prop, key in (("ratingValue", "rating"), ("ratingCount", "votes")):
        meta = soup.select_one(f"[itemtype*=AggregateRating] meta[itemprop={prop}]")
        if meta and (value := _number(str(meta.get("content") or ""))):
            ratings[key] = value if key == "rating" else int(value)

    return ratings


def _players(soup: BeautifulSoup) -> tuple[list[str], str | None]:
    """Embed URLs per player tab, with the trailer told apart from the rest."""
    labels = [tab.get_text(strip=True) for tab in soup.select(".fplayer .tabs-sel > span")]
    players: list[str] = []
    trailer = None

    for index, tab in enumerate(soup.select(".fplayer > .tabs-b")):
        frame = tab.find("iframe")
        if not isinstance(frame, Tag) or not frame.get("src"):
            continue  # an "Інфо" tab — announced, with nothing to play yet

        url = urljoin(BASE, str(frame["src"]))
        label = labels[index] if index < len(labels) else ""
        if label.lower().startswith("трейлер") or "youtube" in url:
            trailer = trailer or url
        else:
            players.append(url)

    return players, trailer


def _paragraphs(description: Tag) -> str:
    """The synopsis. Its paragraphs are `<br><br>`, so they become blank lines."""
    for line_break in description.find_all("br"):
        line_break.replace_with("\n")

    text = "\n".join(line.strip() for line in description.get_text().split("\n"))
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def _number(text: str) -> float | None:
    match = re.search(r"\d+(?:[.,]\d+)?", text)
    return float(match[0].replace(",", ".")) if match else None
