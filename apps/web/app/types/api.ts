/**
 * The wire, spelled out.
 *
 * Mirrors `contracts/openapi.json` — which is generated from the running app
 * (`uv run openapi`), so where this disagrees with that file, this is wrong.
 * Hand-written rather than generated because there is no generator wired into
 * the build yet; when there is, this file is what it replaces.
 *
 * Only what the web launcher actually asks for is here. The box's own
 * endpoints — installs, pairing, the remote, live television — are not, and a
 * type for them would be a promise this app does not keep.
 *
 * Every timestamp is an ISO-8601 string with an offset: that is what FastAPI
 * serialises a `datetime` to.
 */

/** The five catalogue sections. A sixth upstream arrives as `null` — see `Card.type`. */
export type ContentType = 'movie' | 'serial' | 'cartoon-movie' | 'cartoon-series' | 'anime'

export const CONTENT_TYPES: readonly ContentType[] = [
  'movie',
  'serial',
  'cartoon-movie',
  'cartoon-series',
  'anime',
]

export interface Genre {
  name: string
  slug: string
}

export interface YearOption {
  name: string
  slug: string
  /** Whether it covers several years rather than one — `2006-2010`. */
  is_range: boolean
}

export interface PageMeta {
  page: number
  per_page: number
  total: number
  total_pages: number
  has_next_page: boolean
}

export interface ReadySeason {
  number: number
  ready_episodes_count: number
  last_ready_episode: number | null
  last_url_suffix: string | null
}

/** A title in list form — the catalogue, trending, the slider, a search hit. */
export interface Card {
  name: string
  original_name: string
  slug: string
  /** `null` for a section this API does not know yet; `type_raw` still holds what upstream said. */
  type: ContentType | null
  type_raw: string
  /** `film` or `serial`, and independent of `type`: an anime can be either. */
  format: string
  poster_url: string
  genres: Genre[]
  seasons_count: number
  imdb_mark: number | null
  year_start: number | null
  year_end: number | null
  /** Already assembled: `2019`, `2019 – 2023`, `2019 – …`. */
  year_label: string | null
  is_series: boolean
  last_update_page: string | null
  first_ready_season: ReadySeason | null
  last_ready_season: ReadySeason | null
  /** Wide artwork and a synopsis. Trending and the slider only. */
  slider_poster_url: string | null
  slider_url: string | null
  short_description: string | null
  /** A localised string like `1 год 50 хв`, not a machine-readable duration. */
  time: string | null
  country: string | null
  age_restrictions: number | null
  trailer_youtube_id: string | null
  average_rating: number | null
  ratings_count: number | null
}

export interface CardPage {
  items: Card[]
  meta: PageMeta
}

export interface CardList {
  items: Card[]
}

export interface Hit {
  card: Card
  /** The title with the matched span in `<mark>`. Absent more often than not. */
  highlighted_name: string | null
}

export interface HitList {
  items: Hit[]
}

export interface SectionFilters {
  popular_genres: Genre[]
  other_genres: Genre[]
  years: YearOption[]
  total_count: number
}

export interface Filters {
  /** Keyed by `ContentType`. A section this client does not know is still listed. */
  by_type: Record<string, SectionFilters>
  /** Sections upstream grew that the API does not model yet. Empty normally. */
  unknown_types: string[]
}

export interface Credit {
  name: string
  original_name: string
  slug: string
  /** The role played. Always null for a director. */
  character: string | null
  poster_url: string | null
  gender: number
}

export interface Episode {
  number: number
  name: string | null
  air_date: string | null
  /** An unreleased episode is still listed, with nothing behind it. */
  ready: boolean
}

/** The dub or release group, and the embed page behind it. */
export interface Source {
  name: string
  link: string
}

export interface Frame {
  url: string
  source: string
  position: number
  episode_number: number | null
}

export interface Season {
  id: number
  number: number
  description: string
  short_description: string
  frames: Frame[]
  /** Keyed by provider. Filled for a film. */
  player_data: Record<string, Source[]>
  /**
   * Episode number → provider → sources. Filled for a series.
   *
   * The outer key is a *string* even though the API models it as an int: JSON
   * has no other kind of object key, and Pydantic does not pretend otherwise.
   */
  episode_players: Record<string, Record<string, Source[]>>
  /** What the site is willing to show. One listed here may carry no stream. */
  players: string[]
  /** What actually carries one, in the order above. */
  available_players: string[]
  rights_blocked: boolean
  ready_episodes_count: number
  episodes: Episode[]
  release_date: string | null
  poster_url: string | null
  trailer_youtube_id: string | null
  last_ready_episode: number | null
  last_url_suffix: string | null
  /**
   * Whether upstream actually filled this season in. A series returns every
   * season it ever had and the episodes of one; the rest arrive empty, which
   * reads exactly like "nothing to watch" and is not the same thing.
   */
  is_loaded: boolean
  is_episodic: boolean
  is_playable: boolean
  playable_episodes: number[]
}

export interface FranchiseItem {
  name: string
  original_name: string
  slug: string
  format: string
  is_current: boolean
  year: number | null
  imdb_mark: number | null
  poster_url: string | null
  season_number: number | null
}

export interface Franchise {
  name: string
  slug: string
  description: string | null
  items: FranchiseItem[]
}

/** Everything the title page shows. */
export interface Details {
  /** Numeric, and the one `/comments` upstream takes — it will not take a slug. */
  id: number
  name: string
  original_name: string
  slug: string
  type: ContentType | null
  type_raw: string
  format: string
  is_series: boolean
  poster_url: string
  slider_url: string | null
  genres: Genre[]
  seasons: Season[]
  cast: Credit[]
  directors: Credit[]
  average_rating: number | null
  ratings_count: number
  comments_count: number
  imdb_mark: number | null
  year_start: number | null
  year_end: number | null
  age_restrictions: number | null
  short_description: string | null
  time: string | null
  country: string | null
  trailer_youtube_id: string | null
  franchise: Franchise | null
  is_playable: boolean
}

/* ── playback ─────────────────────────────────────────────────────────────── */

export interface ResolvedStream {
  url: string
  /** The player's own words: a quality tag, a dub, or the whole playlist path. */
  label: string | null
  /**
   * `playerjs` when read from the page's configuration, `page-scan` when the
   * page was swept for URLs instead — a guess, and worth treating as one.
   */
  source: string
}

/** Every stream on a player page, best guess first. */
export interface Resolved {
  streams: ResolvedStream[]
}

/* ── what to install, and where from ──────────────────────────────────────── */

/** What the client should do about the version it is running. */
export type UpdateAction = 'none' | 'optional' | 'required'

/**
 * Where an update comes from.
 *
 * `store` sends the user to the shop that installed the app, `self` means the
 * build fetches `url` itself, `auto` means there is nothing to do — a reload of
 * a web build *is* the new version.
 */
export type UpdateChannel = 'store' | 'self' | 'auto'

export interface Update {
  action: UpdateAction
  channel: UpdateChannel
  /** Echoed back, so a log line reads on its own. */
  current: string
  latest: string
  minimum: string
  /** `null` when there is nowhere to go — `auto`, or a build with no download configured. */
  url: string | null
}

/**
 * The answer to `POST /init`.
 *
 * The three nullable fields are null for a client that sends no install id, and
 * this one never does — see `api.init`. They are typed rather than left out
 * because the endpoint can fill them, and a type that pretended otherwise would
 * be a promise about the server that this file has no business making.
 *
 * `account` and `session` restate the account shapes above rather than reusing
 * them, which is what the API itself does: `installs` never imports `accounts`,
 * so if one shape changes the mismatch turns up at the seam.
 */
export interface Init {
  install: { id: string; first_run: boolean; registered_at: string } | null
  account: { id: string; display_name: string; email: string | null; is_guest: boolean } | null
  session: { token: string | null; expires_at: string } | null
  update: Update
  /** Switches this build may see. Empty until something needs one. */
  features: Record<string, boolean>
  /** For a device whose clock is wrong: everything with a deadline is relative to this. */
  server_time: string
}

/* ── accounts ─────────────────────────────────────────────────────────────── */

export interface Account {
  id: string
  display_name: string
  email: string | null
  is_guest: boolean
  is_admin: boolean
}

/** `token` is null when the one you sent still works — keep using it. */
export interface Session {
  token: string | null
  expires_at: string
}

/** A user together with the session that proves it. */
export interface Identity {
  session: Session
  account: Account
}
