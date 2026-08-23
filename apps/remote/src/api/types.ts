/**
 * The shapes this page reads, and nothing else.
 *
 * Deliberately not the whole API. A page that exists to answer one question —
 * "is it you, and do you mean it?" — has no business carrying a model of the
 * catalogue, and a type nobody constructs is a type nobody notices going stale.
 */

/** Whoever is signed in on this phone. */
export interface Account {
  id: string
  display_name: string
  email: string | null
  is_guest: boolean
  is_admin: boolean
}

/** A live session, and the token that proves it. */
export interface Session {
  /** Null when the one you sent still works — the server never repeats one. */
  token: string | null
  expires_at: string
}

/** What comes back from signing in, registering, or becoming a guest. */
export interface Identity {
  session: Session
  account: Account
}

/**
 * A television waiting to be let in.
 *
 * `device_name` is whatever the box called itself. It is not proof of anything
 * — which is exactly why the page shows it: the point of the question is that a
 * person looks at it and decides whether it is their own living room.
 */
export interface DeviceLink {
  code: string
  device_name: string | null
  approved: boolean
  /** Seconds left. Never negative — the server clamps it. */
  expires_in: number
}
