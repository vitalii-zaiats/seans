"""Two catalogues, read into one shape.

Nothing here touches a database and nothing here decides that two rows are the
same film — this is only the part that knows kinostrain writes `originalName`
and kinoukr writes `original_title`, and that one of them hides an IMDb id
inside a player URL.

An `Incoming` is one row of one catalogue, with the claims it makes about its
own identity already pulled out of it. What is done with those claims is
`merging.py`'s business.
"""

import json
import re
import unicodedata
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

#: Somebody else's JSON, read as it came. Spelled out rather than left as
#: `Any` — and read through the four helpers below rather than subscripted,
#: because this is exactly the boundary where a `null` turns up in a field the
#: other side calls a string. Both catalogues do it.
type JsonValue = str | int | float | bool | list["JsonValue"] | dict[str, "JsonValue"] | None
type JsonMap = dict[str, JsonValue]

type SourceName = Literal["kinostrain", "kinoukr"]
type ClaimKind = Literal["imdb", "ashdi"]
type HostName = Literal["ashdi", "tortuga", "vsembed"]
type TitleKind = Literal["film", "serial"]

#: `https://ashdi.vip/vod/133070` and `https://ashdi.vip/serial/6959`. The path
#: segment is part of the id: kinostrain lists a serial as one `vod` per
#: episode while kinoukr hands over a single `serial`, so collapsing the two
#: namespaces onto the bare number merges films that share nothing but a digit.
_ASHDI = re.compile(r"ashdi\.vip/(vod|serial)/(\d+)")
#: kinostrain's third player. Nobody advertises it as an identifier, but the
#: `imdb=` in it is the only canonical id that catalogue carries at all.
_VSEMBED = re.compile(r"vsembed\.[a-z]+/[^\s\"']*?imdb=(tt\d+)")
_HOSTS: tuple[tuple[str, HostName], ...] = (
    ("ashdi.vip", "ashdi"),
    ("tortuga.", "tortuga"),
    ("vsembed.", "vsembed"),
)


@dataclass(frozen=True, slots=True)
class Claim:
    """A statement of identity strong enough to stand alone."""

    kind: ClaimKind
    value: str


@dataclass(frozen=True, slots=True)
class Alias:
    """A spelling, folded for comparison. Never decisive on its own."""

    folded: str
    year: int | None


@dataclass(frozen=True, slots=True)
class EpisodeIn:
    season: int
    number: int
    name: str | None = None


@dataclass(frozen=True, slots=True)
class Play:
    """One playable address, and where in the title it belongs.

    `season` and `episode` are `None` when the catalogue did not say — kinoukr
    gives one link for a whole show and lets the player work it out.
    """

    host: HostName
    external_id: str
    url: str
    label: str | None = None
    season: int | None = None
    episode: int | None = None


@dataclass(frozen=True, slots=True)
class Incoming:
    """One row of one catalogue, in the shape the merge works on."""

    source: SourceName
    external_id: str
    kind: TitleKind
    name: str
    external_url: str | None = None
    original_name: str | None = None
    year_start: int | None = None
    year_end: int | None = None
    poster_url: str | None = None
    description: str | None = None
    imdb_mark: float | None = None
    imdb_votes: int | None = None
    claims: tuple[Claim, ...] = ()
    aliases: tuple[Alias, ...] = ()
    episodes: tuple[EpisodeIn, ...] = ()
    plays: tuple[Play, ...] = ()


def fold(text: str) -> str:
    """A name reduced to what two catalogues can be expected to agree on.

    Accents go because one side writes `Amélie` and the other `Amelie`; case,
    spacing and punctuation go for the same reason. Cyrillic is left whole —
    NFKD would pull `й` apart into `и` and a breve, and that is a different
    letter rather than the same one decorated.
    """
    out = []
    for char in text.lower():
        base = unicodedata.normalize("NFKD", char)[0]
        char = base if base.isascii() and base.isalpha() else char
        if char.isalnum():
            out.append(char)
    return "".join(out)


def aliases_of(*names: str | None, year: int | None) -> tuple[Alias, ...]:
    """Every spelling a title offers, one alias each.

    A name written `Хвиля / Die Welle` is two names: either half is what the
    other catalogue may have picked, and matching on the whole string would
    find neither.
    """
    found = {}
    for name in names:
        for part in (name or "").split("/"):
            folded = fold(part)
            if len(folded) > 2:
                found[folded] = Alias(folded=folded, year=year)
    return tuple(found.values())


def text(row: JsonMap, key: str) -> str | None:
    """The value when it is a non-empty string, `None` for everything else —
    a missing key, a `null`, a number where a name was expected."""
    value = row.get(key)
    return value if isinstance(value, str) and value else None


def whole(row: JsonMap, key: str) -> int | None:
    value = row.get(key)
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def number(row: JsonMap, key: str) -> float | None:
    value = row.get(key)
    if isinstance(value, bool):
        return None
    return float(value) if isinstance(value, int | float) else None


def rows(row: JsonMap, key: str) -> list[JsonMap]:
    """A list of objects, with anything that is not an object dropped."""
    value = row.get(key)
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def _urls(node: object, out: list[str]) -> None:
    """Every URL anywhere inside a payload. `playerData` nests one way for a
    film and another for an episode, and both are somebody else's shape."""
    if isinstance(node, dict):
        for value in node.values():
            _urls(value, out)
    elif isinstance(node, list):
        for value in node:
            _urls(value, out)
    elif isinstance(node, str) and "://" in node:
        out.append(node)


def _host(url: str) -> HostName | None:
    for needle, host in _HOSTS:
        if needle in url:
            return host
    return None


def _claims(urls: Sequence[str], imdb_id: str | None = None) -> tuple[Claim, ...]:
    found: dict[tuple[str, str], Claim] = {}
    if imdb_id:
        found[("imdb", imdb_id)] = Claim(kind="imdb", value=imdb_id)
    for url in urls:
        if match := _VSEMBED.search(url):
            found[("imdb", match.group(1))] = Claim(kind="imdb", value=match.group(1))
        if match := _ASHDI.search(url):
            value = f"{match.group(1)}/{match.group(2)}"
            found[("ashdi", value)] = Claim(kind="ashdi", value=value)
    return tuple(found.values())


def _play(url: str, label: str | None, season: int | None, episode: int | None) -> Play | None:
    host = _host(url)
    if host is None:
        return None
    match = _ASHDI.search(url)
    external = f"{match.group(1)}/{match.group(2)}" if match else url
    return Play(
        host=host, external_id=external, url=url, label=label, season=season, episode=episode
    )


def read_kinostrain(content: Path, seasons: Path | None = None) -> Iterator[Incoming]:
    """`/content/{slug}`, with the seasons a serial does not fill in folded back.

    A serial's own answer carries every season and the episodes of exactly one;
    the rest were fetched separately. Both files are read here so that the
    merge never has to know there were two.
    """
    extra: dict[str, dict[int, JsonMap]] = {}
    if seasons is not None and seasons.exists():
        for line in seasons.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            slug, index, data = text(row, "slug"), whole(row, "season"), row.get("data")
            if slug and index is not None and isinstance(data, dict):
                extra.setdefault(slug, {})[index] = data

    with content.open(encoding="utf-8") as lines:
        for line in lines:
            row = json.loads(line)
            yield _one_kinostrain(row, extra.get(text(row, "slug") or "", {}))


def _one_kinostrain(row: JsonMap, extra: dict[int, JsonMap]) -> Incoming:
    urls: list[str] = []
    plays: list[Play] = []
    episodes: list[EpisodeIn] = []

    for season in rows(row, "seasons"):
        index = whole(season, "number") or 1
        filled = season
        # `players` is the *advertisement* — `["ashdi", "tortuga", "vidsrc"]` —
        # and it is there whether or not any link is. Only `playerData` says
        # whether this season was actually filled in.
        if not season.get("playerData"):
            for candidate in rows(extra.get(index) or {}, "seasons"):
                if whole(candidate, "number") == index:
                    filled = candidate
        _collect_season(filled, index, urls, plays, episodes)

    slug = text(row, "slug") or ""
    name = text(row, "name") or text(row, "originalName") or slug
    year = whole(row, "yearStart")
    return Incoming(
        source="kinostrain",
        external_id=slug,
        external_url=f"https://kinostrain.com/content/{slug}",
        kind="serial" if text(row, "format") == "serial" else "film",
        name=name,
        original_name=text(row, "originalName"),
        year_start=year,
        year_end=whole(row, "yearEnd"),
        poster_url=text(row, "posterUrl"),
        description=text(row, "shortDescription"),
        imdb_mark=number(row, "imdbMark"),
        claims=_claims(urls),
        aliases=aliases_of(text(row, "originalName"), name, year=year),
        episodes=tuple(episodes),
        plays=tuple(plays),
    )


def _entries(season: JsonMap) -> Iterator[tuple[int | None, JsonMap]]:
    """Every `{name, link}` in a season, with the episode it belongs to.

    `playerData` is two different shapes under one name: for a film its keys
    are player names (`ashdi`, `tortuga`), for a serial they are episode
    numbers, and inside an episode it is keyed by player again. The key is what
    tells you which one you are holding — a digit means an episode.
    """
    players = season.get("playerData")
    if not isinstance(players, dict):
        return
    for key, value in players.items():
        if key.isdigit():
            inner = value if isinstance(value, dict) else {}
            for entries in inner.values():
                for entry in entries if isinstance(entries, list) else []:
                    if isinstance(entry, dict):
                        yield int(key), entry
        else:
            for entry in value if isinstance(value, list) else []:
                if isinstance(entry, dict):
                    yield None, entry


def _collect_season(
    season: JsonMap, index: int, urls: list[str], plays: list[Play], episodes: list[EpisodeIn]
) -> None:
    for order, entry in _entries(season):
        link = text(entry, "link")
        if link is None:
            continue
        urls.append(link)
        if play := _play(link, text(entry, "name"), index, order):
            plays.append(play)

    for episode in rows(season, "episodes"):
        order = whole(episode, "number")
        if order is None:
            continue
        episodes.append(EpisodeIn(season=index, number=order, name=text(episode, "name")))
        # An episode object carries `name`, `airDate` and `ready` and no link
        # of its own; the links for it are up in the season's `playerData`,
        # under its number.


def read_kinoukr(path: Path) -> Iterator[Incoming]:
    """One line per title. No seasons, no episodes: a serial is one link."""
    with path.open(encoding="utf-8") as lines:
        for line in lines:
            row = json.loads(line)
            identifier = whole(row, "id")
            title = text(row, "title")
            if identifier is None or title is None:
                # One row in the dump is a 403 with nothing but a title on it.
                continue
            urls: list[str] = []
            _urls(row.get("players"), urls)
            label = text(row, "audio")
            plays = [play for url in urls if (play := _play(url, label, None, None))]
            year = whole(row, "year")
            yield Incoming(
                source="kinoukr",
                external_id=str(identifier),
                external_url=text(row, "url"),
                kind="serial" if (text(row, "kind") or "").endswith("series") else "film",
                name=title,
                original_name=text(row, "original_title"),
                year_start=year,
                year_end=whole(row, "year_end"),
                poster_url=text(row, "poster"),
                description=text(row, "description"),
                imdb_mark=number(row, "imdb"),
                imdb_votes=whole(row, "imdb_votes"),
                claims=_claims(urls, text(row, "imdb_id")),
                aliases=aliases_of(text(row, "original_title"), title, year=year),
                plays=tuple(plays),
            )
