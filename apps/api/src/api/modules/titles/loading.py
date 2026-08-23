"""Turning merged titles into rows.

Kept apart from `merging.py` because the merge is arithmetic over data and this
is a write to a database — and the first is worth testing without the second.

The `slug` is minted here rather than taken from either catalogue: both have
one, they disagree, and a title that loses a source should not lose its
address.
"""

import math
import unicodedata
from collections.abc import Sequence
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession
from t9 import codes_for

from api.modules.titles.merging import Merged
from api.modules.titles.models import (
    KEY_LENGTH,
    Episode,
    Host,
    IdentifierKind,
    Kind,
    Season,
    Source,
    Stream,
    Title,
    TitleAlias,
    TitleIdentifier,
    TitleKey,
    TitleSource,
)
from api.modules.titles.reading import Incoming

#: The most a vote count may add to a score, and how many decades of votes it
#: takes to earn it. Deliberately less than one point.
#:
#: A multiplier was the first attempt and it was wrong: only kinoukr counts
#: votes, so every title that catalogue does not have was ranked as though
#: nobody had watched it. "Family Guy" at 8.1 came fourth behind three films
#: scoring 6.1 to 7.1, which is not a ranking anybody would defend. The score
#: is the signal; the votes are a nudge between titles that scored alike.
VOTE_BONUS = 0.9
VOTE_DECADES = 6

#: Column widths, clamped here rather than widened there. These are somebody
#: else's strings: kinoukr's dub label is occasionally a whole sentence about
#: who recorded it, and a `varchar(4000)` to hold one would be storing a
#: paragraph in a field a picker shows on one line.
NAME = 300
URL = 500
LABEL = 200
FOREIGN_ID = 200
ADDRESS = 120
FOLDED = 200


def fit(value: str | None, limit: int) -> str | None:
    return value if value is None else value[:limit]


def fitted(value: str, limit: int) -> str:
    return value[:limit]


@dataclass(frozen=True, slots=True)
class Loaded:
    """What a load did."""

    titles: int = 0
    sources: int = 0
    identifiers: int = 0
    aliases: int = 0
    seasons: int = 0
    episodes: int = 0
    streams: int = 0
    keys: int = 0
    #: Claims that two titles both wanted. Each is a merge that should have
    #: happened and did not — worth reading afterwards, never worth stopping a
    #: load over.
    contested: tuple[str, ...] = ()


def rank_of(row: Incoming) -> float:
    """What a shortlist is ordered by when the query is ambiguous.

    On a keypad it always is, so this does more work than it looks like. The
    score decides; the vote count breaks a tie between two titles that scored
    alike, and can never carry a worse film past a better one.
    """
    mark = row.imdb_mark or 0.0
    if not row.imdb_votes:
        return mark
    decades = min(math.log10(1 + row.imdb_votes), VOTE_DECADES)
    return mark + VOTE_BONUS * decades / VOTE_DECADES


async def load(session: AsyncSession, merged: Sequence[Merged]) -> Loaded:
    """Write every title. The caller owns the transaction."""
    used: set[str] = set()
    claimed: dict[tuple[str, str], str] = {}
    contested: list[str] = []
    tally = dict.fromkeys(
        ("sources", "identifiers", "aliases", "seasons", "episodes", "streams", "keys"), 0
    )

    for group in merged:
        title = _title(group, used)
        session.add(title)

        for attached in group.rows:
            title.sources.append(
                TitleSource(
                    source=Source(attached.row.source),
                    external_id=fitted(attached.row.external_id, FOREIGN_ID),
                    external_url=fit(attached.row.external_url, URL),
                    name=fitted(attached.row.name, NAME),
                    year=attached.row.year_start,
                    evidence=attached.evidence,
                )
            )
            tally["sources"] += 1

            for claim in attached.row.claims:
                owner = claimed.get((claim.kind, claim.value))
                if owner == title.slug:
                    # Both source rows named it. That is the agreement that put
                    # them together, not a second identifier.
                    continue
                if owner is not None:
                    # `uq_identifier` would refuse the insert. Refusing it here
                    # keeps the load running and names what was refused.
                    contested.append(f"{claim.kind}:{claim.value} — {owner} and {title.slug}")
                    continue
                claimed[(claim.kind, claim.value)] = title.slug
                title.identifiers.append(
                    TitleIdentifier(
                        kind=IdentifierKind(claim.kind), value=fitted(claim.value, ADDRESS)
                    )
                )
                tally["identifiers"] += 1

        for folded, year in {(a.folded, a.year) for row in group.rows for a in row.row.aliases}:
            title.aliases.append(TitleAlias(folded=fitted(folded, FOLDED), year=year))
            tally["aliases"] += 1

        for code in _codes(group):
            title.keys.append(TitleKey(code=code))
            tally["keys"] += 1

        _playable(title, group, tally)

    return Loaded(titles=len(merged), contested=tuple(contested), **tally)


def _title(group: Merged, used: set[str]) -> Title:
    head = group.primary
    return Title(
        slug=_slug(head, used),
        kind=Kind.serial if head.kind == "serial" else Kind.film,
        name=fitted(head.name, NAME),
        original_name=fit(head.original_name, NAME),
        year_start=head.year_start,
        year_end=head.year_end,
        poster_url=fit(head.poster_url, URL),
        description=head.description,
        imdb_mark=head.imdb_mark,
        imdb_votes=max((row.row.imdb_votes or 0) for row in group.rows) or None,
        rank=max(rank_of(row.row) for row in group.rows),
    )


def _codes(group: Merged) -> set[str]:
    """Keypad codes for every name this title answers to.

    Both catalogues' spellings, not only the one that won `primary` — somebody
    typing the other site's title is typing this film either way.
    """
    names = {row.row.name for row in group.rows}
    names |= {row.row.original_name for row in group.rows if row.row.original_name}
    # Truncated before the set, so two codes that shorten to the same thing
    # become one row rather than a unique-constraint violation.
    return {code[:KEY_LENGTH] for name in names for code in codes_for(name)}


def _playable(title: Title, group: Merged, tally: dict[str, int]) -> None:
    """Seasons, episodes, and the streams that hang off them."""
    seasons: dict[int, Season] = {}
    episodes: dict[tuple[int, int], Episode] = {}

    for attached in group.rows:
        for incoming in attached.row.episodes:
            season = seasons.get(incoming.season)
            if season is None:
                season = Season(number=incoming.season)
                seasons[incoming.season] = season
                title.seasons.append(season)
                tally["seasons"] += 1
            spot = (incoming.season, incoming.number)
            if spot not in episodes:
                episodes[spot] = Episode(number=incoming.number, name=fit(incoming.name, NAME))
                season.episodes.append(episodes[spot])
                tally["episodes"] += 1

    seen: set[tuple[str, str]] = set()
    for attached in group.rows:
        for play in attached.row.plays:
            address = (play.host, play.external_id)
            if address in seen:
                # The same upload offered by both catalogues, or by two dubs of
                # one episode. One row, and this is where the duplicate dies.
                continue
            seen.add(address)
            episode = None
            if play.season is not None and play.episode is not None:
                episode = episodes.get((play.season, play.episode))
            title.streams.append(
                Stream(
                    episode=episode,
                    host=Host(play.host),
                    external_id=fitted(play.external_id, ADDRESS),
                    url=fitted(play.url, URL),
                    label=fit(play.label, LABEL),
                    offered_by=Source(attached.row.source),
                )
            )
            tally["streams"] += 1


def _slug(row: Incoming, used: set[str]) -> str:
    """`family-guy-1999`, and a counter when two films really are called that."""
    base = _dashed(row.original_name or row.name) or "title"
    if row.year_start:
        base = f"{base}-{row.year_start}"
    base = base[:190]
    slug, counter = base, 2
    while slug in used:
        slug = f"{base}-{counter}"
        counter += 1
    used.add(slug)
    return slug


#: Ukrainian romanised the way both catalogues romanise their own slugs. Not a
#: standard transliteration — `ч` and `ш` both land on `s`-ish letters and that
#: is fine, because this is an address rather than a spelling.
_LATIN = str.maketrans(
    "абвгґдеєжзиіїйклмнопрстуфхцчшщюяыэ",
    "abvggdeezziiijklmnoprstufhccssuaie",
    "ьъ",
)


#: Vanish rather than separate. An apostrophe is inside a word — `П'ятниця` is
#: one — and NFKD leaves a combining accent behind after taking `é` apart, which
#: would otherwise turn `Amélie` into `ame-lie`.
_GONE = "'\u2019\u02bc`"


def _dashed(name: str) -> str:
    out: list[str] = []
    for char in unicodedata.normalize("NFKD", name.lower()).translate(_LATIN):
        if char in _GONE or unicodedata.combining(char):
            continue
        if char.isalnum() and char.isascii():
            out.append(char)
        elif out and out[-1] != "-":
            out.append("-")
    return "".join(out).strip("-")
