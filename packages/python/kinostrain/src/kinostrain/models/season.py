"""A season, its episodes, and the two shapes its streams arrive in."""

from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import datetime

from kinostrain.jsonread import (
    JsonMap,
    bool_or,
    datetime_or_none,
    int_or_none,
    list_of,
    map_or_none,
    require_int,
    require_str,
    str_list,
    str_list_or_none,
    str_or_none,
)

#: Streams offered for one thing, keyed by provider (`ashdi`, `tortuga`, ...).
Providers = Mapping[str, tuple["PlayerSource", ...]]


@dataclass(frozen=True, slots=True)
class PlayerSource:
    """One playable stream offered by a hosting provider.

    A season can list several sources for the same provider — usually different
    dubs, told apart by `name`.
    """

    #: Label of the dub or release group, e.g. `DniproFilm`.
    name: str
    #: Embeddable player URL on the provider's domain.
    link: str

    @classmethod
    def from_json(cls, json: JsonMap) -> "PlayerSource":
        return cls(
            name=str_or_none(json, "name") or "",
            link=require_str(json, "link", owner="PlayerSource"),
        )


@dataclass(frozen=True, slots=True)
class SeasonFrame:
    """A still or backdrop attached to a season."""

    url: str
    #: Where the image came from. Only `backdrop` appears in captured traffic.
    source: str = ""
    #: Sort order within the season's frame list.
    position: int = 0
    #: Episode this frame belongs to, when it is a still rather than a
    #: season-wide backdrop.
    episode_number: int | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "SeasonFrame":
        return cls(
            url=require_str(json, "url", owner="SeasonFrame"),
            source=str_or_none(json, "source") or "",
            position=int_or_none(json, "position") or 0,
            episode_number=int_or_none(json, "episodeNumber"),
        )


@dataclass(frozen=True, slots=True)
class Episode:
    """One episode of a season."""

    #: 1-based number, and the key into the season's player map.
    number: int
    #: Episode title, when the API has one.
    name: str | None = None
    #: Broadcast date, sent as a plain `YYYY-MM-DD`.
    air_date: datetime | None = None
    #: Whether it is published. An unreleased episode is still listed, with no
    #: streams behind it.
    ready: bool = False

    @classmethod
    def from_json(cls, json: JsonMap) -> "Episode":
        return cls(
            number=require_int(json, "number", owner="Episode"),
            name=str_or_none(json, "name"),
            air_date=datetime_or_none(json, "airDate"),
            ready=bool_or(json, "ready"),
        )


def _providers(raw: JsonMap) -> Providers:
    return {
        key: tuple(PlayerSource.from_json(item) for item in value if isinstance(item, Mapping))
        for key, value in raw.items()
        if isinstance(value, list)
    }


@dataclass(frozen=True, slots=True)
class Season:
    """A season of a series, or the single pseudo-season a film is wrapped in.

    The API ships streams in two different shapes under the same `playerData`
    key. A film's map is keyed by provider (`{"ashdi": [...]}`); a series' map
    is keyed by **episode number**, with the provider map one level further in
    (`{"1": {"ashdi": [...]}}`). Both are parsed here and reach callers through
    the same `sources_for` / `available_players` pair, which take an optional
    episode.
    """

    id: int
    #: 1-based number. A film exposes a single season numbered `1`.
    number: int
    description: str = ""
    short_description: str = ""
    #: Backdrops and episode stills.
    frames: tuple[SeasonFrame, ...] = ()
    #: Streams by provider for a film-shaped season. Empty for a series — see
    #: `episode_players`.
    player_data: Providers = field(default_factory=dict)
    #: Streams by episode number, then by provider. Empty for a film.
    episode_players: Mapping[int, Providers] = field(default_factory=dict)
    #: Provider keys the site is willing to show, in display order. One listed
    #: here may still carry no stream — `available_players()` is what really
    #: plays.
    players: tuple[str, ...] = ()
    #: Playback withheld for rights reasons.
    rights_blocked: bool = False
    ready_episodes_count: int = 0
    #: The episode list. Empty for a film, and for a season not filled in yet.
    episodes: tuple[Episode, ...] = ()
    release_date: datetime | None = None
    poster_url: str | None = None
    trailer_youtube_id: str | None = None
    last_ready_episode: int | None = None
    #: Deep-link suffixes for this season's episodes. Always `null` in captured
    #: traffic, so the element shape is unverified.
    url_suffixes: tuple[str, ...] | None = None
    last_url_suffix: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Season":
        owner = "Season"
        raw = map_or_none(json, "playerData") or {}

        # Episode-keyed when every key is a number. An empty map is neither
        # shape and falls through as a film with no streams.
        episodic = bool(raw) and all(key.lstrip("-").isdigit() for key in raw)

        return cls(
            id=require_int(json, "id", owner=owner),
            number=require_int(json, "number", owner=owner),
            description=str_or_none(json, "description") or "",
            short_description=str_or_none(json, "shortDescription") or "",
            frames=list_of(json, "frames", SeasonFrame.from_json),
            player_data={} if episodic else _providers(raw),
            episode_players=(
                {
                    int(key): _providers(value if isinstance(value, Mapping) else {})
                    for key, value in raw.items()
                }
                if episodic
                else {}
            ),
            players=str_list(json, "players"),
            rights_blocked=bool_or(json, "rightsBlocked"),
            ready_episodes_count=int_or_none(json, "readyEpisodesCount") or 0,
            episodes=list_of(json, "episodes", Episode.from_json),
            release_date=datetime_or_none(json, "releaseDate"),
            poster_url=str_or_none(json, "posterUrl"),
            trailer_youtube_id=str_or_none(json, "trailerYoutubeId"),
            last_ready_episode=int_or_none(json, "lastReadyEpisode"),
            url_suffixes=str_list_or_none(json, "urlSuffixes"),
            last_url_suffix=str_or_none(json, "lastUrlSuffix"),
        )

    @property
    def is_loaded(self) -> bool:
        """Whether the API actually filled this season in.

        `/content/{slug}` returns the full list of a series' seasons but the
        episodes and players of only one; the rest arrive from
        `/content/{slug}?season=N`. Until then they come back with no players,
        no episodes and no streams — which reads exactly like a season with
        nothing to watch, and is not the same thing at all.
        """
        return bool(self.players or self.episodes or self.player_data or self.episode_players)

    @property
    def is_episodic(self) -> bool:
        """Whether streams are addressed per episode rather than per season."""
        return bool(self.episode_players)

    @property
    def playable_episodes(self) -> tuple[int, ...]:
        """Episode numbers that actually have a stream, ascending."""
        return tuple(
            sorted(
                number
                for number, providers in self.episode_players.items()
                if any(sources for sources in providers.values())
            )
        )

    def _map_for(self, episode: int | None) -> Providers:
        """The provider map for `episode`, or for the season itself when it is
        film-shaped. Falls back to the first playable episode when an episodic
        season is asked without one."""
        if not self.is_episodic:
            return self.player_data
        if episode is not None:
            return self.episode_players.get(episode, {})
        playable = self.playable_episodes
        return self.episode_players[playable[0]] if playable else {}

    def available_players(self, *, episode: int | None = None) -> tuple[str, ...]:
        """Provider keys that really carry a stream, in the order `players`
        lists them."""
        found = self._map_for(episode)
        ordered = [key for key in self.players if found.get(key)]
        # A provider that ships a stream without being listed in `players`
        # still plays; keep it rather than hiding it.
        extra = [key for key, sources in found.items() if sources and key not in ordered]
        return tuple(ordered + extra)

    def sources_for(self, provider: str, *, episode: int | None = None) -> tuple[PlayerSource, ...]:
        """Every stream of `provider`, or nothing when it offers none."""
        return self._map_for(episode).get(provider, ())

    @property
    def is_playable(self) -> bool:
        """Whether anything can be watched right now — the whole season for a
        film, any episode for a series."""
        if self.rights_blocked:
            return False
        if self.is_episodic:
            return bool(self.playable_episodes)
        return any(sources for sources in self.player_data.values())
