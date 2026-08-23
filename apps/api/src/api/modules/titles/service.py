"""The module's public face: search a keypad, open a title, rebuild the lot."""

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession

from api.errors import Invalid, NotFound
from api.modules.titles.loading import Loaded, load
from api.modules.titles.merging import merge
from api.modules.titles.models import Episode, Season, Stream, Title
from api.modules.titles.reading import Incoming, read_kinostrain, read_kinoukr
from api.modules.titles.repository import TitleRepository

#: Below this a keypad query is not worth running. One digit selects a third of
#: the index and narrows nothing — the same reason the text search refuses one
#: character.
MIN_KEYS = 2

#: A television draws about a dozen, and asking for more is asking the server to
#: rank rows nobody will scroll to.
MAX_RESULTS = 50


@dataclass(frozen=True, slots=True)
class Watchable:
    """A title with everything needed to play it."""

    title: Title
    seasons: tuple[Season, ...]
    episodes: tuple[Episode, ...]
    streams: tuple[Stream, ...]


@dataclass(slots=True)
class TitleService:
    session: AsyncSession

    @property
    def _titles(self) -> TitleRepository:
        return TitleRepository(self.session)

    async def by_keys(self, keys: str, *, limit: int = 12) -> tuple[Title, ...]:
        """What a remote's number pad found.

        Non-digits are dropped rather than refused: a client may have collected
        them however it likes, and `0` is not a separator here — every word
        start has a code of its own, so there is nothing to separate.
        """
        wanted = "".join(char for char in keys if char.isdigit())
        if len(wanted) < MIN_KEYS:
            raise Invalid(f"press at least {MIN_KEYS} keys")
        return tuple(await self._titles.by_keys(wanted, limit=min(limit, MAX_RESULTS)))

    async def watchable(self, slug: str) -> Watchable:
        title = await self._titles.by_slug(slug)
        if title is None:
            raise NotFound(f"no title {slug!r}")
        seasons = tuple(await self._titles.seasons_for(title.id))
        return Watchable(
            title=title,
            seasons=seasons,
            episodes=tuple(await self._titles.episodes_for([season.id for season in seasons])),
            streams=tuple(await self._titles.streams_for(title.id)),
        )

    async def count(self) -> int:
        return await self._titles.count()

    async def rebuild(self, folder: Path) -> Loaded:
        """Read the dumps, merge them, and replace the catalogue with the result.

        One transaction: the old catalogue is gone only if the new one arrived.
        A partial answer to "what is there to watch" is worse than yesterday's.
        """
        rows = _read(folder)
        if not rows:
            raise Invalid(f"nothing to load from {folder}")
        loaded = await load(self.session, merge(rows))
        return loaded

    async def clear(self) -> None:
        await self._titles.clear()


def _read(folder: Path) -> Sequence[Incoming]:
    """Whichever dumps are there. A missing source is not an error — one
    catalogue is a smaller answer, not a broken one."""
    rows: list[Incoming] = []
    content = folder / "kinostrain_content.jsonl"
    if content.exists():
        rows += read_kinostrain(content, folder / "kinostrain_seasons.jsonl")
    kinoukr = folder / "kinoukr_all.jsonl"
    if kinoukr.exists():
        rows += read_kinoukr(kinoukr)
    return rows
