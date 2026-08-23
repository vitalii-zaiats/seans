/**
 * Whether the terms have been accepted, and which ones.
 *
 * A version rather than a boolean: terms that change are new terms, and a
 * `true` written a year ago says nothing about the text somebody is bound by
 * now. Raise [TERMS_VERSION] when the wording changes in a way that matters and
 * everybody is asked again.
 *
 * In this browser, like everything else here — there is nowhere on the server
 * to put it, and an acceptance that travelled would need an account, which is
 * exactly what this app does not require.
 */

/** Raise this when `pages/terms.vue` changes in substance. */
export const TERMS_VERSION = '1'

const KEY = 'terms.accepted'

/** The routes somebody must be able to read *before* agreeing to anything. */
const READABLE = ['/terms', '/privacy', '/rights']

function read(): string | null {
  if (!import.meta.client) return null
  try {
    return window.localStorage.getItem(KEY)
  } catch {
    // A browser that refuses storage asks on every visit. Annoying, and the
    // right way round: the alternative is treating silence as consent.
    return null
  }
}

export function useTerms() {
  const version = useState<string | null>('terms.version', () => read())
  const declined = useState<boolean>('terms.declined', () => false)
  /**
   * `router.currentRoute` rather than `useRoute()`.
   *
   * This composable is used from `app.vue`, which sits *outside* `<NuxtPage>`,
   * and the route object handed out there does not follow a client-side
   * navigation: clicking through to the terms from the gate changed the address
   * and left the gate up, because as far as it was concerned nothing had moved.
   * The router's own ref is the same value without the seam.
   */
  const current = useRouter().currentRoute

  const accepted = computed(() => version.value === TERMS_VERSION)

  /** The documents stay open: nobody can agree to a text they cannot read. */
  const reading = computed(() => READABLE.some((one) => current.value.path.startsWith(one)))

  const blocked = computed(() => !accepted.value && !reading.value)

  function accept(): void {
    declined.value = false
    version.value = TERMS_VERSION
    try {
      window.localStorage.setItem(KEY, TERMS_VERSION)
    } catch {
      // Then it is asked again next visit, which is the honest failure.
    }
  }

  function decline(): void {
    declined.value = true
  }

  function reconsider(): void {
    declined.value = false
  }

  return { accepted, blocked, declined, reading, accept, decline, reconsider }
}
