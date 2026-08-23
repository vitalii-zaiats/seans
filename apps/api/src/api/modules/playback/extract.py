"""Pulling the streams out of an ashdi player page.

The page hands its configuration to Playerjs:

    player = new Playerjs({ id:"videoplayer167527", file:'https://…/index.m3u8', … })

`file` is one of three things, and telling them apart is the whole job:

* a single URL — a film;
* a comma-separated list with a quality tag each — `[720p]a.m3u8,[1080p]b.m3u8`;
* on a `/serial/` page, a JSON playlist nested dub → season → episode.

That nesting is a habit rather than a contract — a serial with one dub drops the
outer folder, a mini-series has no seasons — so the walk keeps every folder title
it passed and reads the numbers off the titles instead of off the depth.

A port of `packages/dart/ashdi_finder/lib/src/player.dart`, kept close to it on
purpose: when the two disagree, the difference should be a bug in one of them
rather than a design decision nobody wrote down.
"""

import json
import re
from dataclasses import dataclass, field
from typing import Any

_M3U8 = re.compile(r"""https?://[^\s'"\\<>()]+\.m3u8[^\s'"\\<>()]*""")

_PLAYERJS_FILE = re.compile(
    r"""new\s+Playerjs\s*\(\s*\{[\s\S]*?\bfile\s*:\s*(['"])([\s\S]*?)(?<!\\)\1"""
)

_QUALITY = re.compile(r"\[([^\]]+)\]\s*([^,]+)")

_ESCAPE = re.compile(r"\\u([0-9a-fA-F]{4})|\\([\s\S])")

_SEASON = re.compile(r"сезон\s*(\d+)|(\d+)\s*(?:-й\s*)?сезон", re.IGNORECASE)

_EPISODE = re.compile(
    r"(?:сер[ії]я|епізод)\s*(\d+)(?:\s*[-–—]\s*(\d+))?|(\d+)\s*(?:сер[ії]я|епізод)",
    re.IGNORECASE,
)

#: The last resort when a title carries no numbers: `.../foo.s01e02.1080p_268989/...`
_FILE_NAME = re.compile(r"[._/-]s(\d{1,2})e(\d{1,3})", re.IGNORECASE)

_SHORT_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f"}


@dataclass(frozen=True, slots=True)
class Stream:
    url: str
    #: The player's own words: a quality tag, a dub, or the whole playlist path
    #: (`Postmodern / Сезон 1 / Серія 1`).
    label: str | None = None
    #: `playerjs` from the configuration, `page-scan` when it could not be read
    #: and the page was swept for URLs instead. Worth keeping: a page-scan
    #: result is a guess and should be treated as one.
    source: str = "playerjs"


@dataclass(frozen=True, slots=True)
class Episode:
    title: str = ""
    season: int | None = None
    episode: int | None = None
    episode_end: int | None = None
    dub: str | None = None
    streams: tuple[Stream, ...] = field(default_factory=tuple)


def streams(html: str) -> tuple[Stream, ...]:
    """Every `.m3u8` on the page, in document order, deduplicated."""
    config = _config(html)
    found = _config_streams(config) if config is not None else ()

    if not found:
        # Nothing structured. Sweep the page — worse, and better than nothing.
        found = tuple(Stream(url=m.group(0), source="page-scan") for m in _M3U8.finditer(html))

    return _dedupe(found)


def episodes(html: str) -> tuple[Episode, ...]:
    """Every episode a serial page lists, in playlist order.

    Empty for a film: a `/vod/` page plays one file and has no playlist to walk.
    """
    config = _config(html)
    return _playlist(config) if config is not None else ()


def _config(html: str) -> str | None:
    found = _PLAYERJS_FILE.search(html)
    return None if found is None else _unescape(found.group(2))


def _unescape(value: str) -> str:
    """Undoes JS string escaping (`\\/`, `\\"`, `\\u0421`) without touching UTF-8."""

    def one(match: re.Match[str]) -> str:
        code = match.group(1)
        if code is not None:
            return chr(int(code, 16))
        char = match.group(2)
        return _SHORT_ESCAPES.get(char, char)

    return _ESCAPE.sub(one, value)


def _config_streams(config: str) -> tuple[Stream, ...]:
    walked = _playlist(config)
    if walked:
        return tuple(stream for episode in walked for stream in episode.streams)
    return _files(config, None)


def _playlist(value: str) -> tuple[Episode, ...]:
    """The playlist a serial's `file` holds. Empty when it is a plain URL list."""
    trimmed = value.strip()
    if not trimmed.startswith(("[{", "{")):
        return ()
    try:
        return tuple(_walk(json.loads(trimmed), ()))
    except (json.JSONDecodeError, TypeError):
        return ()  # not a playlist after all — read it as URLs


def _walk(node: Any, folders: tuple[str, ...]) -> list[Episode]:
    """Recurses a Playerjs playlist, remembering the folders a leaf sits under."""
    if isinstance(node, list):
        return [found for item in node for found in _walk(item, folders)]
    if not isinstance(node, dict):
        return []

    raw = node.get("title") or node.get("comment")
    title = raw.strip() if isinstance(raw, str) else ""

    folder = node.get("folder")
    if isinstance(folder, list):
        return _walk(folder, (*folders, title) if title else folders)

    file = node.get("file")
    if not isinstance(file, str):
        return []

    return [_episode(title, folders, file)]


def _episode(title: str, folders: tuple[str, ...], file: str) -> Episode:
    season, dub = _season_and_dub(folders)
    episode, episode_end = _episode_numbers(title)

    if season is None or episode is None:
        # Titles are the uploader's words; the file name is the fallback that
        # does not depend on them.
        from_name = _FILE_NAME.search(file)
        if from_name is not None:
            season = season if season is not None else int(from_name.group(1))
            episode = episode if episode is not None else int(from_name.group(2))

    return Episode(
        title=title,
        season=season,
        episode=episode,
        episode_end=episode_end,
        dub=dub,
        # The label keeps the whole path, so a flattened stream still says where
        # it came from.
        streams=_files(file, _join((*folders, title))),
    )


def _season_and_dub(folders: tuple[str, ...]) -> tuple[int | None, str | None]:
    """Which folder was the season, and which one named the voices."""
    season: int | None = None
    dub: str | None = None

    for folder in folders:
        number = _season_number(folder)
        if number is not None:
            season = number
        elif dub is None:
            dub = folder

    return season, dub


def _season_number(title: str) -> int | None:
    found = _SEASON.search(title)
    if found is None:
        return None
    return int(found.group(1) or found.group(2))


def _episode_numbers(title: str) -> tuple[int | None, int | None]:
    found = _EPISODE.search(title)
    if found is None:
        return None, None
    end = found.group(2)
    return int(found.group(1) or found.group(3)), None if end is None else int(end)


def _files(value: str, label: str | None) -> tuple[Stream, ...]:
    """One leaf's `file`: a URL, or several with a quality tag each."""
    return tuple(
        Stream(url=url, label=_join((label, quality)))
        for quality, url in _split_qualities(value)
        if ".m3u8" in url
    )


def _split_qualities(value: str) -> tuple[tuple[str | None, str], ...]:
    """`[720p]a.m3u8,[1080p]b.m3u8` → `(('720p', 'a.m3u8'), ('1080p', 'b.m3u8'))`."""
    tagged = tuple((m.group(1).strip(), m.group(2).strip()) for m in _QUALITY.finditer(value))
    if tagged:
        return tagged

    return tuple((None, part.strip()) for part in value.split(",") if part.strip())


def _join(parts: tuple[str | None, ...]) -> str | None:
    kept = [part.strip() for part in parts if part and part.strip()]
    return " / ".join(kept) if kept else None


def _dedupe(found: tuple[Stream, ...]) -> tuple[Stream, ...]:
    seen: set[str] = set()
    kept: list[Stream] = []
    for stream in found:
        if stream.url not in seen:
            seen.add(stream.url)
            kept.append(stream)
    return tuple(kept)
