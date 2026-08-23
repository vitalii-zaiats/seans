/**
 * One place that knows how to ask the API something.
 *
 * Same-origin, always: the client asks for `/catalogue/…` with no host, and
 * something in front puts the two behind one address — nginx in the image, the
 * dev proxy in `nuxt.config.ts`. That is why there is no base URL to configure
 * and no CORS to arrange, and why the `/proxy/…` image paths the API hands out
 * work without anybody rewriting them.
 */

import type {
  CardList,
  CardPage,
  ContentType,
  Details,
  Filters,
  HitList,
  Identity,
  Init,
  Resolved,
  Schedule,
  TvChannels,
  TvStream,
  Account,
} from '~/types/api'

/**
 * A refusal, with the status intact.
 *
 * The status is kept because the caller acts on it: a 401 signs the browser
 * out, a 404 is "no such title" rather than "the catalogue is down", and the
 * rest is a sentence to put on screen.
 */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
    this.name = 'ApiError'
  }

  get unauthorized(): boolean {
    return this.status === 401
  }

  get missing(): boolean {
    return this.status === 404
  }
}

type Query = Record<string, string | number | string[] | undefined | null>

/** The API answers a refusal as `{"detail": "…"}` — see `api.main`. */
function refusal(error: unknown): ApiError {
  const response = (error as { response?: Response }).response
  const data = (error as { data?: unknown }).data
  const status = response?.status ?? 0

  if (data && typeof data === 'object' && 'detail' in data) {
    const detail = (data as { detail: unknown }).detail
    if (typeof detail === 'string') return new ApiError(status, detail)
    // FastAPI's own validation errors are a list of objects meant for a
    // developer, not for a screen.
    if (Array.isArray(detail)) return new ApiError(status, 'Сервер не прийняв запит')
  }

  // `$fetch` rejects the same way for a dead network as for a blocked origin,
  // and "Failed to fetch" tells the reader nothing they can act on.
  if (!status) return new ApiError(0, 'Немає зв’язку з сервером')
  return new ApiError(status, `Помилка ${status}`)
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  try {
    return await $fetch<T>(path, {
      method: options.method,
      query: options.query,
      body: options.body,
      headers: options.token ? { authorization: `Bearer ${options.token}` } : undefined,
    })
  } catch (error) {
    throw refusal(error)
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE'
  query?: Query
  /** JSON, always: nothing this app sends is a form or a file. */
  body?: Record<string, unknown>
  token?: string | null
}

/**
 * An image address the browser may actually use.
 *
 * The catalogue's own host sends no CORS header, so the API rewrites every
 * poster to a path of its own — `/proxy/…` — and a path is what arrives here.
 * Relative already means "this origin", so there is nothing to do but hand
 * back what came; the function exists so that a caller never has to wonder,
 * and so the one place that would change if the API started sending absolute
 * URLs is this one.
 */
export function imageUrl(url: string | null | undefined): string | null {
  return url && url.length > 0 ? url : null
}

export const api = {
  /** The hero row, with trailer ids and age ratings filled in. */
  slider: (type?: ContentType) => request<CardList>('/catalogue/slider', { query: { type } }),

  /** A home rail, richer than a catalogue card. Not paginated. */
  trending: (type?: ContentType) => request<CardList>('/catalogue/trending', { query: { type } }),

  /** A page of one section. `genres` and `year` take slugs from `filters()`. */
  catalog: (options: {
    type?: ContentType
    page?: number
    genres?: string[]
    year?: string
  }) =>
    request<CardPage>('/catalogue/content', {
      query: { type: options.type, page: options.page, genres: options.genres, year: options.year },
    }),

  /** Genres and year buckets per section, with per-section counts. */
  filters: () => request<Filters>('/catalogue/filters'),

  /** Titles matching `q`. Under two characters the API answers empty. */
  search: (q: string, limit?: number) => request<HitList>('/catalogue/search', { query: { q, limit } }),

  /**
   * Cards for several slugs at once — what "Мій список" and "Продовжити
   * дивитись" are made of. Neither the order nor an entry per slug is
   * guaranteed: upstream answers with what it has.
   */
  cards: (slugs: string[]) =>
    request<CardList>('/catalogue/cards', { method: 'POST', body: { slugs } }),

  /** One title in full. Pass `season` to fill in a season other than the first. */
  content: (slug: string, season?: number) =>
    request<Details>(`/catalogue/content/${encodeURIComponent(slug)}`, { query: { season } }),

  /**
   * What the newest build of a platform is, and where it lives.
   *
   * **Without an install id**, which is the whole reason this page may call it:
   * omit that and the launch is not written down at all — no install row, no
   * account, no session, and an answer carrying only the update plan and the
   * feature flags. A downloads page that registered an install every time
   * somebody looked at it would put a fiction into the statistics the admin
   * dashboard draws.
   *
   * `ver` is what the caller claims to be running. `0.0.0` is honest here: a
   * browser looking at a downloads page is running no build of that platform at
   * all, and the answer we want is "the newest one".
   */
  init: (platform: 'android' | 'web' | 'linux' | 'windows', ver = '0.0.0') =>
    request<Init>('/init', { method: 'POST', body: { platform, ver } }),

  /** Every free channel, with its categories. */
  channels: () => request<TvChannels>('/tv/channels'),

  /**
   * A playable address for a channel.
   *
   * `use_proxy` is not optional here and is the whole reason this works in a
   * browser: the stitched playlist comes from a host that answers no
   * `access-control-allow-origin`, so a page cannot read it. With the flag the
   * address points at `/stream`, which it can.
   *
   * A lease rather than an address — it goes stale after `refresh_in` seconds,
   * so ask again rather than keeping it.
   */
  openChannel: (id: number) =>
    request<TvStream>(`/tv/channels/${id}/stream`, {
      method: 'POST',
      query: { use_proxy: 'true' },
    }),

  /** One channel's programmes for one day. Today when no day is given. */
  schedule: (id: number, day?: string) =>
    request<Schedule>(`/tv/channels/${id}/schedule`, { query: { day } }),

  /**
   * A player page, read for the stream inside it.
   *
   * The catalogue hands out embed pages rather than streams, and a browser can
   * fetch neither: the page's host sends no CORS header, and it wants a
   * `Referer` a page is not allowed to set. `url` is one of the links already
   * in a season's `player_data`.
   */
  resolve: (url: string, where: { season?: number | null; episode?: number | null } = {}) =>
    request<Resolved>('/playback/resolve', {
      method: 'POST',
      body: { url, season: where.season ?? null, episode: where.episode ?? null },
    }),

  /**
   * The same address, fetched somewhere a browser is allowed to read it.
   *
   * A relative path on purpose — see `api.modules.stream` — so it works from
   * whatever host this page was served on.
   */
  streamed: (url: string) => `/stream?url=${encodeURIComponent(url)}`,

  /* ── accounts ───────────────────────────────────────────────────────────── */

  /** Who the token belongs to. 401 when there is none, or it is stale. */
  me: (token: string) => request<Account>('/auth/me', { token }),

  /** A guest on demand — an identity with no email and no password behind it. */
  guest: () => request<Identity>('/auth/guest', { method: 'POST' }),

  /** Turn the guest this browser already is into an account it can log back into. */
  claim: (token: string, body: { email: string; password: string; display_name?: string }) =>
    request<Identity>('/auth/claim', { method: 'POST', body, token }),

  /** An account with no guest behind it. */
  register: (body: { email: string; password: string; display_name?: string }) =>
    request<Identity>('/auth/register', { method: 'POST', body }),

  login: (body: { email: string; password: string }) =>
    request<Identity>('/auth/login', { method: 'POST', body }),

  logout: (token: string) => request<void>('/auth/logout', { method: 'POST', token }),

  /** Deletes the account and its sessions. There is no undo and no tombstone. */
  forget: (token: string) => request<void>('/auth/me', { method: 'DELETE', token }),

  rename: (token: string, display_name: string) =>
    request<Account>('/auth/me', { method: 'PATCH', body: { display_name }, token }),
}
