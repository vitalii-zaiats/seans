"""The full payload of `/content/{slug}` — everything the detail page shows."""

from dataclasses import dataclass

from kinostrain.jsonread import (
    JsonMap,
    float_or_none,
    int_or_none,
    list_of,
    map_or_none,
    require_int,
    require_str,
    str_or_none,
)
from kinostrain.models.common import Genre
from kinostrain.models.enums import ContentType
from kinostrain.models.franchise import Franchise
from kinostrain.models.people import Credit
from kinostrain.models.season import Season


@dataclass(frozen=True, slots=True)
class ContentDetails:
    """One title, in full."""

    #: Numeric id. Required by `/content/{id}/comments`, which does **not**
    #: accept the slug.
    id: int
    name: str
    original_name: str
    slug: str
    #: The `type` field exactly as sent.
    type_raw: str
    #: `film` or `serial`.
    format: str
    poster_url: str
    genres: tuple[Genre, ...] = ()
    #: Seasons in ascending order. A film has exactly one, numbered `1`,
    #: carrying the players.
    seasons: tuple[Season, ...] = ()
    cast: tuple[Credit, ...] = ()
    directors: tuple[Credit, ...] = ()
    #: How many users voted, and how many comments `/content/{id}/comments`
    #: will return in total.
    ratings_count: int = 0
    comments_count: int = 0
    #: Parsed section; `None` for a value unknown to this package, in which
    #: case `type_raw` still holds the original string.
    type: ContentType | None = None
    imdb_mark: float | None = None
    #: Site rating out of 10; `None` until the first vote.
    average_rating: int | None = None
    #: Wide backdrop used behind the title on the detail page.
    slider_url: str | None = None
    year_start: int | None = None
    year_end: int | None = None
    age_restrictions: int | None = None
    short_description: str | None = None
    #: Localised runtime string, e.g. `1 год 50 хв`.
    time: str | None = None
    country: str | None = None
    trailer_youtube_id: str | None = None
    #: Collection this title belongs to, when there is one.
    franchise: Franchise | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "ContentDetails":
        owner = "ContentDetails"
        franchise = map_or_none(json, "franchise")
        return cls(
            id=require_int(json, "id", owner=owner),
            name=require_str(json, "name", owner=owner),
            original_name=require_str(json, "originalName", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            type_raw=require_str(json, "type", owner=owner),
            type=ContentType.try_parse(str_or_none(json, "type")),
            format=require_str(json, "format", owner=owner),
            poster_url=require_str(json, "posterUrl", owner=owner),
            genres=list_of(json, "genres", Genre.from_json),
            seasons=list_of(json, "seasons", Season.from_json),
            cast=list_of(json, "cast", Credit.from_json),
            directors=list_of(json, "directors", Credit.from_json),
            ratings_count=int_or_none(json, "ratingsCount") or 0,
            comments_count=int_or_none(json, "commentsCount") or 0,
            imdb_mark=float_or_none(json, "imdbMark"),
            average_rating=int_or_none(json, "averageRating"),
            slider_url=str_or_none(json, "sliderUrl"),
            year_start=int_or_none(json, "yearStart"),
            year_end=int_or_none(json, "yearEnd"),
            age_restrictions=int_or_none(json, "ageRestrictions"),
            short_description=str_or_none(json, "shortDescription"),
            time=str_or_none(json, "time"),
            country=str_or_none(json, "country"),
            trailer_youtube_id=str_or_none(json, "trailerYoutubeId"),
            franchise=None if franchise is None else Franchise.from_json(franchise),
        )

    @property
    def is_series(self) -> bool:
        return self.format == "serial"

    @property
    def first_season(self) -> Season | None:
        """The season carrying a film's streams, i.e. its only one."""
        return self.seasons[0] if self.seasons else None

    @property
    def first_playable_season(self) -> Season | None:
        """Lowest-numbered season with at least one stream — where a first
        watch starts.

        A long-running series often lists every season it ever had while
        carrying data for only some, so this is not simply `seasons[0]`.
        """
        playable = [season for season in self.seasons if season.is_playable]
        return min(playable, key=lambda season: season.number) if playable else None

    @property
    def latest_playable_season(self) -> Season | None:
        """Highest-numbered season with at least one stream."""
        playable = [season for season in self.seasons if season.is_playable]
        return max(playable, key=lambda season: season.number) if playable else None

    @property
    def is_playable(self) -> bool:
        """Whether anything at all can be watched right now."""
        return any(season.is_playable for season in self.seasons)
