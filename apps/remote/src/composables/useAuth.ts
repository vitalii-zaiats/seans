/**
 * Who this phone is, across reloads.
 *
 * A module-level singleton rather than a per-component thing: the sign-in card
 * and the approve button are two components asking the same question, and two
 * copies of the answer is how one of them ends up a step behind.
 */

import { computed, readonly, ref } from 'vue'

import { ApiError, api } from '@/api/client'
import type { Account } from '@/api/types'

const TOKEN_KEY = 'super-movies.remote.token'

function stored(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY)
  } catch {
    // Private browsing, or storage switched off. The session then lasts as long
    // as the tab does, which is long enough to approve one television.
    return null
  }
}

function remember(token: string | null): void {
  try {
    if (token === null) localStorage.removeItem(TOKEN_KEY)
    else localStorage.setItem(TOKEN_KEY, token)
  } catch {
    /* the token holds in memory either way */
  }
}

const token = ref<string | null>(stored())
const account = ref<Account | null>(null)
const checking = ref(false)
const busy = ref(false)
const error = ref<string | null>(null)

/**
 * Turn a stored token back into a person, or throw it away.
 *
 * Called once when the page opens. A token that no longer works is dropped
 * rather than kept and retried, because the only thing this page does with an
 * identity is spend it, and finding out it was worthless at that moment is the
 * worst possible time.
 */
async function restore(): Promise<void> {
  const held = token.value
  if (held === null) return

  checking.value = true
  try {
    account.value = await api.me(held)
  } catch (failure) {
    if (failure instanceof ApiError && failure.unauthorized) {
      token.value = null
      remember(null)
    }
    account.value = null
  } finally {
    checking.value = false
  }
}

async function attempt(work: () => Promise<{ session: { token: string | null }; account: Account }>) {
  busy.value = true
  error.value = null
  try {
    const identity = await work()
    // Null means "the one you sent still works", which cannot happen here —
    // both of these mint a session. Guarded anyway: the alternative is storing
    // `null` over a token that was fine.
    if (identity.session.token !== null) {
      token.value = identity.session.token
      remember(identity.session.token)
    }
    account.value = identity.account
    return true
  } catch (failure) {
    error.value = failure instanceof Error ? failure.message : 'Не вдалося увійти'
    return false
  } finally {
    busy.value = false
  }
}

export function useAuth() {
  return {
    token: readonly(token),
    account: readonly(account),
    /** Whether a stored token is still being checked. */
    checking: readonly(checking),
    /** Whether a sign-in or a registration is in flight. */
    busy: readonly(busy),
    error: readonly(error),
    signedIn: computed(() => account.value !== null),

    restore,

    signIn: (email: string, password: string) =>
      attempt(() => api.login(email, password)),

    signUp: (email: string, password: string, displayName?: string) =>
      attempt(() => api.register(email, password, displayName)),

    signOut(): void {
      token.value = null
      account.value = null
      error.value = null
      remember(null)
    },

    clearError(): void {
      error.value = null
    },
  }
}
