/**
 * One place that knows how to ask the API something.
 *
 * Two things live here that would otherwise be sprinkled through the app: the
 * bearer header, and the rule that a refusal is an exception rather than a
 * value somebody might forget to check.
 */

import type { Account, Identity, Overview, Platform, RecordPage } from './types'

/** Unset means "the origin this page was served from" — see `vite.config.ts`. */
const ORIGIN = import.meta.env.VITE_API_URL ?? ''

/**
 * The version of the API this bundle speaks — see `api.versions` on the server.
 *
 * Folded into the base rather than written at every call, because it belongs to
 * the whole of what this file knows how to ask for: a version is a set of paths
 * and payloads, and a bundle speaks exactly one.
 */
const V = '/api/v1'

/** Where every path below is appended. */
const BASE = `${ORIGIN}${V}`

/**
 * A refusal, with the status intact.
 *
 * The status is kept because the caller acts on it: a 401 signs the dashboard
 * out, a 403 says "you are somebody, just not an admin", and everything else is
 * a message to show. Collapsing them into one `Error` would make the sign-out
 * path guesswork.
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

  get forbidden(): boolean {
    return this.status === 403
  }
}

type Query = Record<string, string | number | undefined | null>

function url(path: string, query: Query = {}): string {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(query)) {
    // A blank search box and an unset filter both mean "do not narrow", and
    // sending `q=` would ask the API to match the empty string instead.
    if (value !== undefined && value !== null && value !== '') {
      search.set(key, String(value))
    }
  }
  const tail = search.toString()
  return `${BASE}${path}${tail ? `?${tail}` : ''}`
}

/** The API answers a refusal as `{"detail": "..."}` — see `api.main`. */
async function refusal(response: Response): Promise<string> {
  try {
    const body: unknown = await response.json()
    if (body && typeof body === 'object' && 'detail' in body) {
      const detail = (body as { detail: unknown }).detail
      if (typeof detail === 'string') return detail
      // FastAPI's own validation errors come back as a list of objects. They
      // are for a developer, not for this screen, so they get a plain sentence.
      if (Array.isArray(detail)) return 'Сервер не прийняв запит'
    }
  } catch {
    // A gateway that fell over answers HTML, or nothing at all.
  }
  return `Помилка ${response.status}`
}

async function request<T>(path: string, token: string | null, query?: Query): Promise<T> {
  let response: Response
  try {
    response = await fetch(url(path, query), {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    })
  } catch {
    // `fetch` rejects for a dead network or a blocked origin, and the message
    // it carries ("Failed to fetch") tells the reader nothing they can act on.
    throw new ApiError(0, 'Не вдалося зв’язатися з API')
  }
  if (!response.ok) throw new ApiError(response.status, await refusal(response))
  return (await response.json()) as T
}

export interface OverviewQuery {
  days: number
  activeDays: number
  top: number
}

export interface RecordQuery {
  limit: number
  offset: number
  platform: Platform | null
  search: string
}

export const api = {
  async login(email: string, password: string): Promise<Identity> {
    let response: Response
    try {
      response = await fetch(url('/auth/login'), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email, password }),
      })
    } catch {
      throw new ApiError(0, 'Не вдалося зв’язатися з API')
    }
    if (!response.ok) throw new ApiError(response.status, await refusal(response))
    return (await response.json()) as Identity
  },

  me(token: string): Promise<Account> {
    return request<Account>('/auth/me', token)
  },

  overview(token: string, query: OverviewQuery): Promise<Overview> {
    return request<Overview>('/admin/stats/installs', token, {
      days: query.days,
      active_days: query.activeDays,
      top: query.top,
    })
  },

  records(token: string, query: RecordQuery): Promise<RecordPage> {
    return request<RecordPage>('/admin/stats/installs/recent', token, {
      limit: query.limit,
      offset: query.offset,
      platform: query.platform,
      q: query.search.trim(),
    })
  },
}
