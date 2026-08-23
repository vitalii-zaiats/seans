"""The list-shaped view of a title, and the season summary that rides along."""

from dataclasses import dataclass
from datetime import datetime

from kinostrain.jsonread import (
    JsonMap,
    datetime_or_none,
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


@dataclass(frozen=True, slots=True)
class ReadySeason:
    """Publication progress of a season, as summarised on a card.

    Arrives as `firstReadySeason` / `lastReadySeason`; both are absent for
    content with nothing published yet.
    """

    #: 1-based season number.
    number: int
    #: How many episodes of it are watchable.
    ready_episodes_count: int = 0
    #: Newest watchable episode; `None` for films, whose single "season"
    #: carries no episode list.
    last_ready_episode: int | None = None
    #: Path fragment the website appends to deep-link the newest episode,
    #: e.g. `season-1/episode-8`.
    last_url_suffix: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "ReadySeason":
        return cls(
            number=require_int(json, "number", owner="ReadySeason"),
            ready_episodes_count=int_or_none(json, "readyEpisodesCount") or 0,
            last_ready_episode=int_or_none(json, "lastReadyEpisode"),
            last_url_suffix=str_or_none(json, "lastUrlSuffix"),
        )


@dataclass(frozen=True, slots=True)
class ContentCard:
    """A title in list form.

    One class covers `/catalog`, `/trending`, `/slider` and
    `POST /content/cards`, because they return the same object with different
    amounts of detail. Fields only some endpoints populate are optional — each
    one says where it comes from.
    """

    #: Localised title.
    name: str
    #: Title in the original language.
    original_name: str
    #: Stable identifier, used by `/content/{slug}` and the website URL.
    slug: str
    #: The `type` field exactly as sent by the server.
    type_raw: str
    #: Presentation form, `film` or `serial`. Independent of `type`: an `anime`
    #: can be either.
    format: str
    poster_url: str
    genres: tuple[Genre, ...] = ()
    #: Number of seasons; `1` for films.
    seasons_count: int = 0
    #: Parsed section, or `None` for a value this package does not know yet —
    #: `type_raw` always holds the original string.
    type: ContentType | None = None
    #: IMDb score. Sent as `7` or `6.4`; both land here as a float.
    imdb_mark: float | None = None
    year_start: int | None = None
    #: End year of a finished multi-year series; `None` for films and ongoing.
    year_end: int | None = None
    #: When the page was last touched upstream. Absent on `/slider`.
    last_update_page: datetime | None = None
    first_ready_season: ReadySeason | None = None
    last_ready_season: ReadySeason | None = None
    #: Wide artwork. `/trending` and `/slider` only.
    slider_poster_url: str | None = None
    slider_url: str | None = None
    #: Synopsis. `/trending` and `/slider`.
    short_description: str | None = None
    #: Human-readable runtime, e.g. `1 год 50 хв` — a localised string, not a
    #: machine-readable duration.
    time: str | None = None
    #: Production country, as a display string. `/trending` and `/slider`.
    country: str | None = None
    #: Minimum age, e.g. `18`. `/slider` only.
    age_restrictions: int | None = None
    #: YouTube id of the trailer. `/slider` only.
    trailer_youtube_id: str | None = None
    #: Site rating and its vote count. `POST /content/cards` only.
    average_rating: int | None = None
    ratings_count: int | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "ContentCard":
        owner = "ContentCard"
        first_ready = map_or_none(json, "firstReadySeason")
        last_ready = map_or_none(json, "lastReadySeason")
        return cls(
            name=require_str(json, "name", owner=owner),
            original_name=require_str(json, "originalName", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            type_raw=require_str(json, "type", owner=owner),
            type=ContentType.try_parse(str_or_none(json, "type")),
            format=require_str(json, "format", owner=owner),
            poster_url=require_str(json, "posterUrl", owner=owner),
            genres=list_of(json, "genres", Genre.from_json),
            seasons_count=int_or_none(json, "seasonsCount") or 0,
            imdb_mark=float_or_none(json, "imdbMark"),
            year_start=int_or_none(json, "yearStart"),
            year_end=int_or_none(json, "yearEnd"),
            last_update_page=datetime_or_none(json, "lastUpdatePage"),
            first_ready_season=None if first_ready is None else ReadySeason.from_json(first_ready),
            last_ready_season=None if last_ready is None else ReadySeason.from_json(last_ready),
            slider_poster_url=str_or_none(json, "sliderPosterUrl"),
            slider_url=str_or_none(json, "sliderUrl"),
            short_description=str_or_none(json, "shortDescription"),
            time=str_or_none(json, "time"),
            country=str_or_none(json, "country"),
            age_restrictions=int_or_none(json, "ageRestrictions"),
            trailer_youtube_id=str_or_none(json, "trailerYoutubeId"),
            average_rating=int_or_none(json, "averageRating"),
            ratings_count=int_or_none(json, "ratingsCount"),
        )

    @property
    def is_series(self) -> bool:
        """Whether this card describes something with episodes."""
        return self.format == "serial"

    @property
    def year_label(self) -> str | None:
        """`2019` for a film, `2019 – 2023` for a finished series, `2019 – …`
        while it is still running. `None` when no start year came back."""
        if self.year_start is None:
            return None
        if not self.is_series:
            return str(self.year_start)
        if self.year_end is None:
            return f"{self.year_start} – …"
        return f"{self.year_start} – {self.year_end}"
