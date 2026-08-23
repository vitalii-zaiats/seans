/**
 * Who is watching, if anybody says.
 *
 * The whole of the account here is a bearer token in `localStorage` and the
 * name that comes back for it. Nothing on the site needs one — the catalogue is
 * open, and the two lists are this browser's — so the sign-in screen is an
 * offer rather than a gate, and every screen works with `account` null.
 *
 * No QR pairing: that is the television asking a phone to sign it in, and a
 * browser with a keyboard has a shorter way to the same place.
 */

import type { Account, Identity } from '~/types/api'

const TOKEN_KEY = 'auth.token'

export function useAccount() {
  const token = useState<string | null>('account.token', () => {
    if (!import.meta.client) return null
    try {
      return window.localStorage.getItem(TOKEN_KEY)
    } catch {
      return null
    }
  })
  const account = useState<Account | null>('account.who', () => null)
  const checked = useState<boolean>('account.checked', () => false)

  function keep(identity: Identity): void {
    // A null token means "the one you sent still works" — see `SessionOut`.
    if (identity.session.token) {
      token.value = identity.session.token
      try {
        window.localStorage.setItem(TOKEN_KEY, identity.session.token)
      } catch {
        // A browser that refuses storage still gets this session; it just does
        // not get the next one.
      }
    }
    account.value = identity.account
    checked.value = true
  }

  function drop(): void {
    token.value = null
    account.value = null
    checked.value = true
    try {
      window.localStorage.removeItem(TOKEN_KEY)
    } catch {
      // Nothing was stored to begin with.
    }
  }

  /**
   * Reads the token back, once per page load.
   *
   * A stale token is dropped rather than kept and retried: it will fail the
   * same way on every screen, and a sign-in offer is a better thing to show
   * than a name that turns out not to be signed in.
   */
  async function load(): Promise<void> {
    if (checked.value) return
    checked.value = true
    if (!token.value) return
    try {
      account.value = await api.me(token.value)
    } catch (error) {
      if (error instanceof ApiError && error.unauthorized) drop()
    }
  }

  /**
   * A guest: an identity with no email and no password behind it.
   *
   * The same thing the box asks for when somebody picks "продовжити як гість" —
   * a name the server knows, that can be turned into a real account later
   * (`POST /auth/claim`) without losing what it already stands for.
   */
  const keepGuest = async () => keep(await api.guest())

  /**
   * Put an email and a password on the guest this browser already is.
   *
   * The same row, not a new one — which is the whole reason to be a guest
   * first: whatever the server has tied to that identity stays tied to it, and
   * signing in from a laptop later reaches the same account. `POST /auth/register`
   * would instead leave the guest behind, still watched-on and unreachable.
   *
   * The token is rotated by the server: the old one was handed out under weaker
   * terms, and now it opens a whole account.
   */
  async function claim(email: string, password: string, display_name?: string): Promise<void> {
    const current = token.value
    if (!current) throw new ApiError(401, 'Немає сесії гостя')
    keep(await api.claim(current, { email, password, display_name }))
  }

  const signIn = async (email: string, password: string) => keep(await api.login({ email, password }))

  const register = async (email: string, password: string, display_name?: string) =>
    keep(await api.register({ email, password, display_name }))

  /**
   * The way back to local-only: deletes the account and every session on it.
   *
   * `DELETE /auth/me`, and it is the server's own word for this — the row goes,
   * not a flag on it. The two lists stay: they are this browser's and were
   * never on the server to delete.
   */
  async function forget(): Promise<void> {
    const current = token.value
    if (!current) return
    await api.forget(current)
    drop()
  }

  async function signOut(): Promise<void> {
    const current = token.value
    drop()
    // Best effort: the session is already gone as far as this browser is
    // concerned, and a server that cannot be reached should not leave somebody
    // looking signed in.
    if (current) await api.logout(current).catch(() => undefined)
  }

  return { token, account, checked, load, keepGuest, claim, signIn, register, signOut, forget }
}
