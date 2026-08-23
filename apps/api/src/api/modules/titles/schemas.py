"""What the routes answer with."""

from pydantic import BaseModel

from api.modules.titles.models import Episode, Stream, Title
from api.modules.titles.service import Watchable


class TitleOut(BaseModel):
    """A card. What a shortlist is made of."""

    slug: str
    kind: str
    name: str
    original_name: str | None
    year_start: int | None
    year_end: int | None
    poster_url: str | None
    imdb_mark: float | None

    @classmethod
    def of(cls, title: Title) -> "TitleOut":
        return cls(
            slug=title.slug,
            kind=title.kind.value,
            name=title.name,
            original_name=title.original_name,
            year_start=title.year_start,
            year_end=title.year_end,
            poster_url=title.poster_url,
            imdb_mark=title.imdb_mark,
        )


class TitleList(BaseModel):
    items: list[TitleOut]

    @classmethod
    def of(cls, titles: tuple[Title, ...]) -> "TitleList":
        return cls(items=[TitleOut.of(title) for title in titles])


class StreamOut(BaseModel):
    """One playable address.

    `episode` is null far more often than it looks like it should be, and that
    is the data rather than a gap: one catalogue hands over a single link for a
    whole serial and lets the player deal with the episodes.
    """

    host: str
    url: str
    label: str | None
    season: int | None
    episode: int | None
    offered_by: str


class EpisodeOut(BaseModel):
    season: int
    number: int
    name: str | None


class SourceOut(BaseModel):
    """Who says this title exists, and what made us believe they mean the same
    one. `evidence` is `imdb+ashdi+name`, or `sole` when nothing agreed."""

    source: str
    external_id: str
    external_url: str | None
    name: str
    year: int | None
    evidence: str


class DetailsOut(BaseModel):
    title: TitleOut
    description: str | None
    sources: list[SourceOut]
    episodes: list[EpisodeOut]
    streams: list[StreamOut]

    @classmethod
    def of(cls, watchable: Watchable) -> "DetailsOut":
        seasons = {season.id: season.number for season in watchable.seasons}
        episodes = {episode.id: episode for episode in watchable.episodes}
        return cls(
            title=TitleOut.of(watchable.title),
            description=watchable.title.description,
            sources=[
                SourceOut(
                    source=source.source.value,
                    external_id=source.external_id,
                    external_url=source.external_url,
                    name=source.name,
                    year=source.year,
                    evidence=source.evidence,
                )
                for source in watchable.title.sources
            ],
            episodes=[
                EpisodeOut(
                    season=seasons.get(episode.season_id, 0),
                    number=episode.number,
                    name=episode.name,
                )
                for episode in watchable.episodes
            ],
            streams=[_stream(stream, episodes, seasons) for stream in watchable.streams],
        )


def _stream(stream: Stream, episodes: dict[int, Episode], seasons: dict[int, int]) -> StreamOut:
    episode = episodes.get(stream.episode_id) if stream.episode_id else None
    return StreamOut(
        host=stream.host.value,
        url=stream.url,
        label=stream.label,
        season=seasons.get(episode.season_id) if episode else None,
        episode=episode.number if episode else None,
        offered_by=stream.offered_by.value,
    )
