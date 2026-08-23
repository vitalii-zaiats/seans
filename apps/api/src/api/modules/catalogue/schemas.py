"""What the catalogue endpoints hand back.

A near-passthrough of the shapes `kinostrain` parses, with two differences that
matter. The wire names are snake_case here, because that is what the rest of
this API speaks; and an unknown content type comes back as `null` with the
original string beside it, so a section upstream adds does not break a client.
"""

from datetime import datetime

from kinostrain import (
    CatalogFilters,
    ContentCard,
    ContentDetails,
    ContentType,
    ContentTypeFilters,
    Credit,
    Episode,
    Franchise,
    FranchiseItem,
    Genre,
    Page,
    PageMeta,
    Person,
    PlayerSource,
    ReadySeason,
    SearchResult,
    Season,
    SeasonFrame,
    YearOption,
)
from pydantic import BaseModel

from api.settings import settings


def proxied(url: str | None) -> str | None:
    """An image address a browser is allowed to use.

    The catalogue's own host sends no CORS header, so a browser fetches the
    bytes and then cannot paint them — see `api.modules.proxy`. Rewriting the
    address here rather than in every client means one place decides, and a
    client that never had the problem (a native build) still works: the path is
    ours either way.

    A **path**, not a URL, for the reason `verify_path` is one: this server does
    not know what address it is reached on, and whatever asked does. A client
    resolves it against the base it already called.
    """
    if not url:
        return None
    upstream = settings.proxy_upstream.rstrip("/")
    if not url.startswith(f"{upstream}/"):
        # Somewhere else's, and by now that means somewhere that allows a
        # browser to read it. Relaying those would be paying for nothing.
        return url
    return f"/proxy/{url[len(upstream) + 1 :]}"


class GenreOut(BaseModel):
    name: str
    slug: str

    @classmethod
    def of(cls, genre: Genre) -> "GenreOut":
        return cls(name=genre.name, slug=genre.slug)


class YearOut(BaseModel):
    name: str
    slug: str
    #: Whether it covers several years rather than one — `2006-2010`.
    is_range: bool

    @classmethod
    def of(cls, year: YearOption) -> "YearOut":
        return cls(name=year.name, slug=year.slug, is_range=year.is_range)


class PageMetaOut(BaseModel):
    page: int
    per_page: int
    total: int
    total_pages: int
    has_next_page: bool

    @classmethod
    def of(cls, meta: PageMeta) -> "PageMetaOut":
        return cls(
            page=meta.page,
            per_page=meta.per_page,
            total=meta.total,
            total_pages=meta.total_pages,
            has_next_page=meta.has_next_page,
        )


class ReadySeasonOut(BaseModel):
    number: int
    ready_episodes_count: int
    last_ready_episode: int | None
    last_url_suffix: str | None

    @classmethod
    def of(cls, ready: ReadySeason) -> "ReadySeasonOut":
        return cls(
            number=ready.number,
            ready_episodes_count=ready.ready_episodes_count,
            last_ready_episode=ready.last_ready_episode,
            last_url_suffix=ready.last_url_suffix,
        )


class CardOut(BaseModel):
    """A title in list form — the catalogue, trending, the slider, a search hit."""

    name: str
    original_name: str
    slug: str
    #: `null` for a section this API does not know yet; `type_raw` still holds
    #: what upstream said, so a client can show it rather than dropping the row.
    type: ContentType | None
    type_raw: str
    #: `film` or `serial`, and independent of `type`: an anime can be either.
    format: str
    poster_url: str
    genres: list[GenreOut]
    seasons_count: int
    imdb_mark: float | None
    year_start: int | None
    year_end: int | None
    #: A label already assembled: `2019`, `2019 – 2023`, `2019 – …`.
    year_label: str | None
    is_series: bool
    last_update_page: datetime | None
    first_ready_season: ReadySeasonOut | None
    last_ready_season: ReadySeasonOut | None
    #: Wide artwork and a synopsis. Trending and the slider only.
    slider_poster_url: str | None
    slider_url: str | None
    short_description: str | None
    #: A localised string like `1 год 50 хв`, not a machine-readable duration.
    time: str | None
    country: str | None
    age_restrictions: int | None
    trailer_youtube_id: str | None
    average_rating: int | None
    ratings_count: int | None

    @classmethod
    def of(cls, card: ContentCard) -> "CardOut":
        return cls(
            name=card.name,
            original_name=card.original_name,
            slug=card.slug,
            type=card.type,
            type_raw=card.type_raw,
            format=card.format,
            poster_url=proxied(card.poster_url) or card.poster_url,
            genres=[GenreOut.of(one) for one in card.genres],
            seasons_count=card.seasons_count,
            imdb_mark=card.imdb_mark,
            year_start=card.year_start,
            year_end=card.year_end,
            year_label=card.year_label,
            is_series=card.is_series,
            last_update_page=card.last_update_page,
            first_ready_season=(
                None
                if card.first_ready_season is None
                else ReadySeasonOut.of(card.first_ready_season)
            ),
            last_ready_season=(
                None
                if card.last_ready_season is None
                else ReadySeasonOut.of(card.last_ready_season)
            ),
            slider_poster_url=proxied(card.slider_poster_url),
            slider_url=proxied(card.slider_url),
            short_description=card.short_description,
            time=card.time,
            country=card.country,
            age_restrictions=card.age_restrictions,
            trailer_youtube_id=card.trailer_youtube_id,
            average_rating=card.average_rating,
            ratings_count=card.ratings_count,
        )


class CardPage(BaseModel):
    items: list[CardOut]
    meta: PageMetaOut

    @classmethod
    def of(cls, page: Page[ContentCard]) -> "CardPage":
        return cls(
            items=[CardOut.of(one) for one in page.items],
            meta=PageMetaOut.of(page.meta),
        )


class CardList(BaseModel):
    items: list[CardOut]

    @classmethod
    def of(cls, cards: tuple[ContentCard, ...]) -> "CardList":
        return cls(items=[CardOut.of(one) for one in cards])


class HitOut(BaseModel):
    """A search hit: a thinner card, plus what the server matched."""

    card: CardOut
    #: The title with the matched span in `<mark>`. Absent more often than not.
    highlighted_name: str | None

    @classmethod
    def of(cls, hit: SearchResult) -> "HitOut":
        return cls(card=CardOut.of(hit.card), highlighted_name=hit.highlighted_name)


class HitList(BaseModel):
    items: list[HitOut]

    @classmethod
    def of(cls, hits: tuple[SearchResult, ...]) -> "HitList":
        return cls(items=[HitOut.of(one) for one in hits])


class SectionFiltersOut(BaseModel):
    popular_genres: list[GenreOut]
    other_genres: list[GenreOut]
    years: list[YearOut]
    total_count: int

    @classmethod
    def of(cls, filters: ContentTypeFilters) -> "SectionFiltersOut":
        return cls(
            popular_genres=[GenreOut.of(one) for one in filters.popular_genres],
            other_genres=[GenreOut.of(one) for one in filters.other_genres],
            years=[YearOut.of(one) for one in filters.years],
            total_count=filters.total_count,
        )


class FiltersOut(BaseModel):
    by_type: dict[str, SectionFiltersOut]
    #: Sections upstream grew that this API does not model yet. Empty normally.
    unknown_types: list[str]

    @classmethod
    def of(cls, filters: CatalogFilters) -> "FiltersOut":
        return cls(
            by_type={
                section.slug: SectionFiltersOut.of(one) for section, one in filters.by_type.items()
            },
            unknown_types=list(filters.unknown_type_keys),
        )


class PersonOut(BaseModel):
    name: str
    original_name: str
    slug: str
    gender: int
    career_roles: list[str]
    poster_url: str | None

    @classmethod
    def of(cls, person: Person) -> "PersonOut":
        return cls(
            name=person.name,
            original_name=person.original_name,
            slug=person.slug,
            gender=int(person.gender),
            career_roles=list(person.career_roles),
            poster_url=proxied(person.poster_url),
        )


class PersonPage(BaseModel):
    items: list[PersonOut]
    meta: PageMetaOut

    @classmethod
    def of(cls, page: Page[Person]) -> "PersonPage":
        return cls(
            items=[PersonOut.of(one) for one in page.items],
            meta=PageMetaOut.of(page.meta),
        )


class CreditOut(BaseModel):
    name: str
    original_name: str
    slug: str
    #: The role played. Always null for a director.
    character: str | None
    poster_url: str | None
    gender: int

    @classmethod
    def of(cls, credit: Credit) -> "CreditOut":
        return cls(
            name=credit.name,
            original_name=credit.original_name,
            slug=credit.slug,
            character=credit.character,
            poster_url=proxied(credit.poster_url),
            gender=int(credit.gender),
        )


class EpisodeOut(BaseModel):
    number: int
    name: str | None
    air_date: datetime | None
    #: An unreleased episode is still listed, with nothing behind it.
    ready: bool

    @classmethod
    def of(cls, episode: Episode) -> "EpisodeOut":
        return cls(
            number=episode.number,
            name=episode.name,
            air_date=episode.air_date,
            ready=episode.ready,
        )


class SourceOut(BaseModel):
    #: The dub or release group — `DniproFilm`.
    name: str
    link: str

    @classmethod
    def of(cls, source: PlayerSource) -> "SourceOut":
        return cls(name=source.name, link=source.link)


class FrameOut(BaseModel):
    url: str
    source: str
    position: int
    episode_number: int | None

    @classmethod
    def of(cls, frame: SeasonFrame) -> "FrameOut":
        return cls(
            url=proxied(frame.url) or frame.url,
            source=frame.source,
            position=frame.position,
            episode_number=frame.episode_number,
        )


class SeasonOut(BaseModel):
    """A season, or the single pseudo-season a film is wrapped in.

    `player_data` is keyed by provider for a film; `episode_players` is keyed by
    episode number and then by provider for a series. Exactly one of them is
    filled — upstream ships both shapes under the same key, and flattening them
    would be a lie about which is which.
    """

    id: int
    number: int
    description: str
    short_description: str
    frames: list[FrameOut]
    player_data: dict[str, list[SourceOut]]
    episode_players: dict[int, dict[str, list[SourceOut]]]
    #: What the site is willing to show. One listed here may carry no stream.
    players: list[str]
    #: What actually carries one, in the order above.
    available_players: list[str]
    rights_blocked: bool
    ready_episodes_count: int
    episodes: list[EpisodeOut]
    release_date: datetime | None
    poster_url: str | None
    trailer_youtube_id: str | None
    last_ready_episode: int | None
    last_url_suffix: str | None
    #: Whether upstream actually filled this season in. A series returns every
    #: season it ever had and the episodes of one; the rest arrive empty, which
    #: reads exactly like "nothing to watch" and is not the same thing.
    is_loaded: bool
    is_episodic: bool
    is_playable: bool
    playable_episodes: list[int]

    @classmethod
    def of(cls, season: Season) -> "SeasonOut":
        return cls(
            id=season.id,
            number=season.number,
            description=season.description,
            short_description=season.short_description,
            frames=[FrameOut.of(one) for one in season.frames],
            player_data={
                provider: [SourceOut.of(one) for one in sources]
                for provider, sources in season.player_data.items()
            },
            episode_players={
                episode: {
                    provider: [SourceOut.of(one) for one in sources]
                    for provider, sources in providers.items()
                }
                for episode, providers in season.episode_players.items()
            },
            players=list(season.players),
            available_players=list(season.available_players()),
            rights_blocked=season.rights_blocked,
            ready_episodes_count=season.ready_episodes_count,
            episodes=[EpisodeOut.of(one) for one in season.episodes],
            release_date=season.release_date,
            poster_url=proxied(season.poster_url),
            trailer_youtube_id=season.trailer_youtube_id,
            last_ready_episode=season.last_ready_episode,
            last_url_suffix=season.last_url_suffix,
            is_loaded=season.is_loaded,
            is_episodic=season.is_episodic,
            is_playable=season.is_playable,
            playable_episodes=list(season.playable_episodes),
        )


class FranchiseItemOut(BaseModel):
    name: str
    original_name: str
    slug: str
    format: str
    is_current: bool
    year: int | None
    imdb_mark: float | None
    poster_url: str | None
    season_number: int | None

    @classmethod
    def of(cls, item: FranchiseItem) -> "FranchiseItemOut":
        return cls(
            name=item.name,
            original_name=item.original_name,
            slug=item.slug,
            format=item.format,
            is_current=item.is_current,
            year=item.year,
            imdb_mark=item.imdb_mark,
            poster_url=proxied(item.poster_url),
            season_number=item.season_number,
        )


class FranchiseOut(BaseModel):
    name: str
    slug: str
    description: str | None
    items: list[FranchiseItemOut]

    @classmethod
    def of(cls, franchise: Franchise) -> "FranchiseOut":
        return cls(
            name=franchise.name,
            slug=franchise.slug,
            description=franchise.description,
            items=[FranchiseItemOut.of(one) for one in franchise.items],
        )


class DetailsOut(BaseModel):
    """Everything the title page shows."""

    #: Numeric, and the one `/comments` upstream takes — it will not take a slug.
    id: int
    name: str
    original_name: str
    slug: str
    type: ContentType | None
    type_raw: str
    format: str
    is_series: bool
    poster_url: str
    slider_url: str | None
    genres: list[GenreOut]
    seasons: list[SeasonOut]
    cast: list[CreditOut]
    directors: list[CreditOut]
    average_rating: int | None
    ratings_count: int
    comments_count: int
    imdb_mark: float | None
    year_start: int | None
    year_end: int | None
    age_restrictions: int | None
    short_description: str | None
    time: str | None
    country: str | None
    trailer_youtube_id: str | None
    franchise: FranchiseOut | None
    is_playable: bool

    @classmethod
    def of(cls, details: ContentDetails) -> "DetailsOut":
        return cls(
            id=details.id,
            name=details.name,
            original_name=details.original_name,
            slug=details.slug,
            type=details.type,
            type_raw=details.type_raw,
            format=details.format,
            is_series=details.is_series,
            poster_url=proxied(details.poster_url) or details.poster_url,
            slider_url=proxied(details.slider_url),
            genres=[GenreOut.of(one) for one in details.genres],
            seasons=[SeasonOut.of(one) for one in details.seasons],
            cast=[CreditOut.of(one) for one in details.cast],
            directors=[CreditOut.of(one) for one in details.directors],
            average_rating=details.average_rating,
            ratings_count=details.ratings_count,
            comments_count=details.comments_count,
            imdb_mark=details.imdb_mark,
            year_start=details.year_start,
            year_end=details.year_end,
            age_restrictions=details.age_restrictions,
            short_description=details.short_description,
            time=details.time,
            country=details.country,
            trailer_youtube_id=details.trailer_youtube_id,
            franchise=None if details.franchise is None else FranchiseOut.of(details.franchise),
            is_playable=details.is_playable,
        )
