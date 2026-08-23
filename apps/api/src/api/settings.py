"""Configuration, from the environment. Prefix `API_`."""

from collections.abc import Mapping, Sequence

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="API_", env_file=".env", extra="ignore")

    # Port 5433, not 5432: another stack already owns the usual one locally.
    database_url: str = "postgresql+asyncpg://movies:movies@127.0.0.1:5433/movies"

    host: str = "127.0.0.1"
    port: int = 8000
    reload: bool = False

    # The wildcard deliberately means *no credentials* — see `main.create_app`.
    cors_origins: list[str] = ["*"]

    # --- identity -----------------------------------------------------------
    # An install *is* its token, and an install lasts as long as the app stays
    # on the device. A short session would sign the television out overnight.
    session_ttl_days: int = 365

    # Where a phone goes to approve a television — `apps/remote`, at `/r/<code>`.
    # A path, not a host: the server has no idea what address this install is
    # reached on, and whatever drew the QR does.
    link_base: str = "/r"

    # --- releases -----------------------------------------------------------
    # The floor and the ceiling. Below `min_version` the app is told it must
    # update; between the two, that it may.
    min_version: str = "0.0.0"
    latest_version: str = "0.0.0"
    # Per-platform overrides, because android and windows do not ship together.
    # A platform absent from these falls back to the two above.
    min_versions: dict[str, str] = {}
    latest_versions: dict[str, str] = {}

    # Where a build that updates *itself* fetches the new one. Never used for a
    # Play Store install — see `api.modules.release.service`.
    self_update_url: str | None = None
    # The listing a Play Store install is sent to instead.
    # Must match `applicationId` in `apps/tv/android/app/build.gradle.kts`.
    # It is what `store_url` below is built from, so a stale value here is a
    # link in every `/init` response pointing at an app nobody published.
    android_package: str = "tv.seans.launcher"

    # --- images -------------------------------------------------------------
    # The one host `/proxy` mirrors. A path and nothing else can be asked for,
    # so this can never become an open relay.
    proxy_upstream: str = "https://api.kinostrain.com"
    proxy_timeout: float = 20.0

    # --- streams ------------------------------------------------------------
    # Which hosts `/stream` may fetch from. Unlike `/proxy` above, that endpoint
    # takes a URL — HLS names its own addresses and there is no path to mirror —
    # so this list is what stands in for that rule.
    #
    # A leading dot means "this domain and anything under it", which is how a
    # CDN's hosts get covered without enumerating them. `["*"]` turns the list
    # off and is a decision to make on purpose; even then nothing that resolves
    # to a private address is fetched. Empty refuses everything.
    #
    # `fastad.pro` is not a typo and not ours: sweet.tv's own `/tv/…/stream`
    # answers with a stitched playlist served from there, and refusing it would
    # mean refusing the channels this API hands out itself.
    stream_hosts: list[str] = [".ashdi.vip", ".sweet.tv", ".fastad.pro"]

    # --- playback -----------------------------------------------------------
    # The player pages this API is willing to read, by host. Same rule as
    # `stream_hosts`: a leading dot covers everything under a domain.
    playback_hosts: list[str] = [".ashdi.vip"]
    # What the player page expects to have been opened from. It serves a
    # different page — or none — without it.
    playback_referer: str = "https://kinostrain.com/"
    playback_timeout: float = 20.0

    # --- catalogue ----------------------------------------------------------
    # Where the catalogue is asked from.
    #
    # kinostrain.com is licensed for Ukraine and answers a request from
    # anywhere else with the metadata intact and `player_data` **empty** — the
    # title looks browsable and turns out to be unplayable. Measured, not
    # guessed: the same `/catalogue/content/susidi-zverhu` returns three
    # players to a Ukrainian address and none to a German one.
    #
    # Only this client needs it. ashdi's player pages and its CDN answer a
    # German address perfectly well (200 on both), and so does sweet.tv,
    # including opening a stream — so no video is routed through here and the
    # bandwidth stays where it was.
    #
    #     API_CATALOGUE_PROXY=http://user:pass@host:port
    #     API_CATALOGUE_PROXY=socks5://host:1080
    catalogue_proxy: str | None = None
    catalogue_timeout: float = 20.0

    # What their own site sends. Upstream does not check it today — a plain curl
    # works — but it costs nothing, and it is the header a service like this
    # starts checking first.
    catalogue_headers: dict[str, str] = {
        "Origin": "https://kinostrain.com",
        "Referer": "https://kinostrain.com/",
    }
    # Genres change when one is added.
    catalogue_filters_ttl: float = 3600.0
    # A home rail: the same answer for every box that starts up.
    catalogue_rail_ttl: float = 300.0

    # --- television ---------------------------------------------------------
    # One device identity for this instance. To sweet.tv that is a single box
    # opening every stream we hand out — fine at this size, and the fix when it
    # is not is to pass each install's own uuid rather than invent more here.
    sweet_tv_uuid: str = "b6f1c0de-0000-4000-8000-000000000001"
    # The channel list changes when a channel is added, not per viewer.
    tv_catalogue_ttl: float = 300.0
    # A day's programmes are settled well before the day is.
    tv_schedule_ttl: float = 3600.0

    # --- features -----------------------------------------------------------
    # Switches the app asks about at start-up.
    #
    # The names are the launcher's own section ids, so a client reads one with
    # `features[tab.id] ?? true` and needs no table to translate. A name absent
    # from the answer is on — which is what makes adding a section a change in
    # the app rather than a deploy here.
    features: dict[str, bool] = {}
    # Names forced off for a Play Store install, whatever `features` says.
    #
    # Google reviews what that build may do, and the answer is "less": the film
    # catalogue and the free channels are third-party streams, and a build that
    # offers them is a build that gets pulled. Arbitrary M3U playlists are the
    # same argument only more so: nobody vets what is on somebody else's list.
    # Everything else — the home screen, the launcher half — stays.
    store_disabled_features: list[str] = ["catalog", "tv", "playlists"]

    @property
    def session_ttl_seconds(self) -> int:
        return self.session_ttl_days * 24 * 60 * 60

    def min_for(self, platform: str) -> str:
        return self.min_versions.get(platform, self.min_version)

    def latest_for(self, platform: str) -> str:
        return self.latest_versions.get(platform, self.latest_version)

    @property
    def store_url(self) -> str:
        return f"https://play.google.com/store/apps/details?id={self.android_package}"

    @property
    def feature_flags(self) -> Mapping[str, bool]:
        return self.features

    @property
    def store_disabled(self) -> Sequence[str]:
        return self.store_disabled_features


settings = Settings()
