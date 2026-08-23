/**
 * One place that knows how to ask the API something.
 *
 * Two things live here that would otherwise be sprinkled through the app: the
 * bearer header, and the rule that a refusal is an exception rather than a
 * value somebody might forget to check.
 */

import type { Account, DeviceLink, Identity } from './types'

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
 * The status is kept because this page acts on it, and each one means something
 * different to whoever is holding the phone: a 401 says the session went stale,
 * a 404 says the code on the television is not a code any more, a 409 says
 * somebody else got there first. Collapsing them into one `Error` would turn
 * every one of those into "щось пішло не так".
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

  /** No such code. Expired, mistyped, or already finished with. */
  get missing(): boolean {
    return this.status === 404
  }

  /** Somebody else approved this one. */
  get taken(): boolean {
    return this.status === 409
  }

  /** The code ran out while the page was open. */
  get invalid(): boolean {
    return this.status === 400
  }
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

interface Options {
  method?: string
  token?: string | null
  body?: unknown
}

async function request<T>(path: string, options: Options = {}): Promise<T> {
  const { method = 'GET', token = null, body } = options

  let response: Response
  try {
    response = await fetch(`${BASE}${path}`, {
      method,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    // `fetch` rejects for a dead network or a blocked origin, and the message
    // it carries ("Failed to fetch") tells the reader nothing they can act on.
    throw new ApiError(0, 'Не вдалося зв’язатися з API')
  }
  if (!response.ok) throw new ApiError(response.status, await refusal(response))
  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

export const api = {
  /** What is being asked for, for the page about to say yes. */
  link(code: string): Promise<DeviceLink> {
    return request<DeviceLink>(`/auth/device/${encodeURIComponent(code)}`)
  },

  /**
   * Say yes, as whoever this phone is signed in as.
   *
   * The only step in the whole dance that needs an identity, and it is this
   * one's — the television never gets to prove anything.
   */
  approve(code: string, token: string): Promise<DeviceLink> {
    return request<DeviceLink>('/auth/device/approve', {
      method: 'POST',
      token,
      body: { code },
    })
  },

  login(email: string, password: string): Promise<Identity> {
    return request<Identity>('/auth/login', {
      method: 'POST',
      body: { email, password },
    })
  },

  /**
   * An account with no guest behind it.
   *
   * Which is what somebody arriving from a QR code has: they came here to sign
   * a television in, not to be given a history they never made.
   */
  register(email: string, password: string, displayName?: string): Promise<Identity> {
    return request<Identity>('/auth/register', {
      method: 'POST',
      body: {
        email,
        password,
        ...(displayName ? { display_name: displayName } : {}),
      },
    })
  },

  me(token: string): Promise<Account> {
    return request<Account>('/auth/me', { token })
  },
}
