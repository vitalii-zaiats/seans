"""kinostrain.com — read through its own JSON API rather than its HTML.

The site has a public API, and a crawler that scraped the pages instead would be
choosing the brittle half of the same service: markup changes when somebody
restyles a card, and the API changes when the data does.

So this source is a crawler in shape only. `page_url` is a catalogue query,
`parse` reads the answer, and the `Fetcher` never learns the difference — a body
is a body.

    GET /api/catalog?page=2        the listing
    GET /api/content/{slug}        one title, in full

Parsing is the `kinostrain` package's job, not this file's. It already models
these payloads and is tested against captured ones; repeating that here would be
two parsers to keep in step, and the second one would lose.

**Why crawl a service we can already call.** Because calling it live makes every
screen in the app depend on somebody else's uptime, rate limit and CORS policy,
and because a catalogue of our own can hold two sources at once. Which is the
point of the `kind` mapping below.
"""

import json
from typing import Any, TypedDict, cast

from kinostrain import ContentCard, ContentDetails
from kinostrain import Page as ApiPage

from crawlers.models import Item
from crawlers.source import Source, register

BASE = "https://api.kinostrain.com/api"

#: Where a person would open the title. Kept beside the API address rather than
#: instead of it: the engine fetches `Item.url`, and that has to be the API's.
SITE = "https://kinostrain.com"

#: This service's sections, said in the vocabulary `kinoukr` already uses.
#:
#: Not cosmetic. Two sources are only worth crawling into one catalogue if they
#: agree on what a thing *is* — otherwise a merge produces two rows for the same
#: film that nothing can line up. `kinoukr` was here first, so its words win.
KINDS = {
    "movie": "film",
    "serial": "series",
    "cartoon-movie": "cartoon",
    "cartoon-series": "cartoon-series",
    "anime": "anime",
}


class Title(TypedDict, total=False):
    """What this source adds, flat in `Item.extra`.

    Every key is optional, because the payloads differ: a film has no episodes,
    an announcement has no players, a title nobody has rated has no score.
    """

    slug: str  # the identity on this service, and what the site URL is built of
    site_url: str  # where a person would open it
    id: int  # numeric, and the only thing the comments endpoint accepts
    kind: str  # film | series | cartoon | cartoon-series | anime — see KINDS
    kind_raw: str  # what the service actually said, for a section we do not know
    original_title: str
    year: int
    year_end: int  # only for a series, and only once it has stopped running
    imdb: float
    rating: int  # the site's own score out of ten, and how many voted
    votes: int
    genres: list[str]  # slugs, not display names — stable across languages
    seasons_count: int
    description: str
    duration: str  # localised: "1 год 50 хв", not a machine-readable length
    country: str
    age: int
    trailer: str  # a YouTube id, not a URL
    directors: list[str]
    cast: list[str]
    players: list[str]  # embed URLs, the same shape `kinoukr` produces
    seasons: list[dict[str, Any]]  # the full structure — see `_seasons`


@register
class Kinostrain(Source):
    name = "kinostrain"
    # Everything this service publishes is dubbed into Ukrainian.
    language = "uk"
    # Every card has a page of its own, and that page is where the players,
    # the cast and the episodes are.
    item_pages = True

    def page_url(self, number: int) -> str:
        return f"{BASE}/catalog?page={number}"

    def parse(self, html: str) -> list[Item]:
        """The catalogue page. `html` is JSON here — the engine only has bodies."""
        payload = json.loads(html)
        if not isinstance(payload, dict):
            return []
        page = ApiPage.from_json(payload, ContentCard.from_json)
        return [_card(card) for card in page.items]

    def parse_item(self, html: str, url: str) -> Item | None:
        """One title in full.

        `None` for anything that is not a title payload — a 404 body, an error
        envelope — which leaves the listing card standing on its own.
        """
        payload = json.loads(html)
        data = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(data, dict):
            return None
        return _details(ContentDetails.from_json(data))


def _card(card: ContentCard) -> Item:
    """A catalogue entry, as much of a title as a listing knows."""
    extra: dict[str, Any] = {
        "slug": card.slug,
        "site_url": f"{SITE}/{card.slug}",
        "kind_raw": card.type_raw,
        "seasons_count": card.seasons_count,
    }
    if kind := KINDS.get(card.type_raw):
        extra["kind"] = kind
    if card.original_name and card.original_name != card.name:
        extra["original_title"] = card.original_name
    if card.year_start is not None:
        extra["year"] = card.year_start
    if card.year_end is not None:
        extra["year_end"] = card.year_end
    if card.imdb_mark is not None:
        extra["imdb"] = card.imdb_mark
    if card.genres:
        extra["genres"] = [genre.slug for genre in card.genres]

    return Item(
        title=card.name,
        # The API's address, not the site's: this is what the engine fetches for
        # `--details`, and what the sinks then store the title under.
        url=f"{BASE}/content/{card.slug}",
        poster=card.poster_url or None,
        extra=cast(Title, extra),
    )


def _details(details: ContentDetails) -> Item:
    """The title page: everything a catalogue of our own would need to hold."""
    extra: dict[str, Any] = {
        "id": details.id,
        "slug": details.slug,
        "site_url": f"{SITE}/{details.slug}",
        "kind_raw": details.type_raw,
    }
    if kind := KINDS.get(details.type_raw):
        extra["kind"] = kind
    if details.original_name and details.original_name != details.name:
        extra["original_title"] = details.original_name
    if details.year_start is not None:
        extra["year"] = details.year_start
    if details.year_end is not None:
        extra["year_end"] = details.year_end
    if details.imdb_mark is not None:
        extra["imdb"] = details.imdb_mark
    if details.average_rating is not None:
        extra["rating"] = details.average_rating
        extra["votes"] = details.ratings_count
    if details.genres:
        extra["genres"] = [genre.slug for genre in details.genres]
    if details.short_description:
        extra["description"] = details.short_description
    if details.time:
        extra["duration"] = details.time
    if details.country:
        extra["country"] = details.country
    if details.age_restrictions is not None:
        extra["age"] = details.age_restrictions
    if details.trailer_youtube_id:
        extra["trailer"] = details.trailer_youtube_id
    if details.directors:
        extra["directors"] = [one.name for one in details.directors]
    if details.cast:
        extra["cast"] = [one.name for one in details.cast]

    seasons = _seasons(details)
    if seasons:
        extra["seasons"] = seasons
    players = _players(details)
    if players:
        extra["players"] = players

    return Item(
        title=details.name,
        url=f"{BASE}/content/{details.slug}",
        poster=details.poster_url or None,
        extra=cast(Title, extra),
    )


def _seasons(details: ContentDetails) -> list[dict[str, Any]]:
    """Every season, and only the ones the service actually filled in.

    A series lists every season it ever had and carries the episodes and players
    of exactly one; the rest arrive empty and mean "not fetched", not "nothing to
    watch". Storing those would put a season with no episodes in the catalogue
    and no way to tell it from one that genuinely has none — so an unloaded
    season is skipped, and a crawl that wants the rest asks for them by number.
    """
    seasons = []

    for season in details.seasons:
        if not season.is_loaded:
            continue

        entry: dict[str, Any] = {
            "number": season.number,
            "players": sorted(season.available_players()),
        }
        if season.episodes:
            entry["episodes"] = [
                {
                    "number": episode.number,
                    "title": episode.name,
                    "ready": episode.ready,
                    **(
                        {"air_date": episode.air_date.date().isoformat()}
                        if episode.air_date
                        else {}
                    ),
                }
                for episode in season.episodes
            ]
        if season.is_episodic:
            entry["sources"] = {
                str(number): {
                    provider: [source.link for source in sources]
                    for provider, sources in providers.items()
                    if sources
                }
                for number, providers in sorted(season.episode_players.items())
            }
        else:
            entry["sources"] = {
                provider: [source.link for source in sources]
                for provider, sources in season.player_data.items()
                if sources
            }
        seasons.append(entry)

    return seasons


def _players(details: ContentDetails) -> list[str]:
    """Embed URLs, in the shape `kinoukr` produces.

    A film's are its own; a series' are its first playable episode's, because
    that is the address a player opens and the rest follow from inside it. The
    whole per-episode map is in `seasons` for anybody who needs more.
    """
    season = details.first_playable_season
    if season is None:
        return []

    links: list[str] = []
    for provider in season.available_players():
        links.extend(source.link for source in season.sources_for(provider))
    return list(dict.fromkeys(links))
