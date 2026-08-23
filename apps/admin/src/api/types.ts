/**
 * The wire, spelled out.
 *
 * These mirror `apps/api/src/api/modules/stats/schemas.py` and the two account
 * shapes this dashboard signs in with. Hand-written rather than generated
 * because there is no generator in the repo yet: when `contracts/openapi.json`
 * starts being produced, this file is what it replaces.
 *
 * Every timestamp is an ISO-8601 string with an offset, because that is what
 * FastAPI serialises a `datetime` to. `day` is a plain `YYYY-MM-DD`.
 */

/** The four the API accepts. A fifth here without one there is a 422. */
export type Platform = 'android' | 'linux' | 'windows' | 'web'

export const PLATFORMS: readonly Platform[] = ['android', 'linux', 'windows', 'web']

export interface Window {
  days: number
  active_days: number
  since: string
  /** Exclusive. */
  until: string
}

export interface Trend {
  value: number
  previous: number
  /** `0.12` is up twelve percent. `null` when the previous window was empty. */
  change: number | null
}

export interface Day {
  /** `YYYY-MM-DD`, UTC. */
  day: string
  created: number
  /**
   * Installs whose *most recent* launch fell on this day — a floor, not a count
   * of activity. Yesterday's shrinks as those installs come back.
   */
  seen: number
}

export interface Slice {
  /** Null where the dimension has no value — no installer outside android. */
  name: string | null
  installs: number
  active: number
}

export interface Overview {
  generated_at: string
  window: Window
  /** Every install ever, ignoring the window. */
  total: number
  created: Trend
  active: Trend
  /** One entry per day of the window, silent days included. */
  daily: Day[]
  platforms: Slice[]
  versions: Slice[]
  vendors: Slice[]
}

export interface InstallRecord {
  /** The uuid the client generated, never the row's own id. */
  id: string
  platform: string
  vendor: string | null
  version: string
  registered_at: string
  last_seen_at: string
}

export interface RecordPage {
  items: InstallRecord[]
  total: number
  limit: number
  offset: number
}

export interface Account {
  id: string
  display_name: string
  email: string | null
  is_guest: boolean
  is_admin: boolean
}

export interface Identity {
  session: { token: string | null; expires_at: string }
  account: Account
}
