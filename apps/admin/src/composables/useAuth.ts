/**
 * Who is looking, and the token that proves it.
 *
 * Module-level state rather than a store: there is exactly one session per tab,
 * and a library to hold one string would be more machinery than the thing it
 * holds. Everything that needs it imports the same refs.
 *
 * The token lives in `localStorage`, which means a script running on this
 * origin could read it. That is the accepted trade for "signing in once a year
 * instead of once a tab", and it is only defensible because this bundle loads
 * nothing from anywhere else.
 */

import { computed, readonly, ref } from 'vue'

import { ApiError, api } from '@/api/client'
import type { Account } from '@/api/types'

const STORAGE_KEY = 'super-movies.admin.token'

function stored(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY)
  } catch {
    // Private mode, or storage switched off. Signing in still works; it just
    // will not survive a reload.
    return null
  }
}

function remember(token: string | null): void {
  try {
    if (token === null) localStorage.removeItem(STORAGE_KEY)
    else localStorage.setItem(STORAGE_KEY, token)
  } catch {
    /* see `stored` */
  }
}

const token = ref<string | null>(stored())
const account = ref<Account | null>(null)
/** True until the stored token has been checked — the app shows a splash. */
const restoring = ref<boolean>(token.value !== null)
const error = ref<string | null>(null)
const busy = ref(false)

/**
 * Signed in *and an admin*. The API refuses everything else anyway; this is so
 * the dashboard can say why instead of drawing four empty cards.
 */
const authorised = computed(() => token.value !== null && account.value?.is_admin === true)

function forget(): void {
  token.value = null
  account.value = null
  remember(null)
}

export function useAuth() {
  async function restore(): Promise<void> {
    const held = token.value
    if (held === null) {
      restoring.value = false
      return
    }
    try {
      account.value = await api.me(held)
    } catch (cause) {
      // Only a refusal means the token is dead. A network blip must not sign
      // somebody out — they would come back to a login form and no explanation.
      if (cause instanceof ApiError && cause.unauthorized) forget()
      else error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      restoring.value = false
    }
  }

  async function signIn(email: string, password: string): Promise<void> {
    busy.value = true
    error.value = null
    try {
      const identity = await api.login(email, password)
      if (!identity.account.is_admin) {
        // The credentials were right. Saying so, rather than "wrong password",
        // is the difference between a person retyping forever and a person
        // asking somebody for the role.
        error.value = 'Цей акаунт не має прав адміністратора'
        return
      }
      // `token` is null when the API kept a session the caller already had —
      // which cannot happen on login, but the shape allows it, so it is checked
      // rather than asserted.
      const issued = identity.session.token
      if (issued === null) {
        error.value = 'Сервер не видав токен'
        return
      }
      token.value = issued
      account.value = identity.account
      remember(issued)
    } catch (cause) {
      error.value =
        cause instanceof ApiError && cause.status === 401
          ? 'Невірна пошта або пароль'
          : cause instanceof Error
            ? cause.message
            : String(cause)
    } finally {
      busy.value = false
    }
  }

  function signOut(): void {
    // Deliberately local. `POST /auth/logout` would revoke the token server
    // side, and revoking the session an admin is holding on their phone
    // because they closed a browser tab is not what the button says.
    forget()
    error.value = null
  }

  /** Called by data loaders when the API refuses: a dead token signs us out. */
  function rejected(cause: unknown): void {
    if (cause instanceof ApiError && cause.unauthorized) forget()
  }

  return {
    token: readonly(token),
    account: readonly(account),
    authorised,
    restoring: readonly(restoring),
    busy: readonly(busy),
    error,
    restore,
    signIn,
    signOut,
    rejected,
  }
}
