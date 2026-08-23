/**
 * Asking the catalogue about a word somebody is still typing.
 *
 * Shared by the field in the bar and the page behind it, because the awkward
 * parts are the same in both and neither is about layout: the API answers
 * anything under two characters empty without a round trip (which is what makes
 * this safe to call on a keystroke), and two requests in flight can come back
 * in the other order.
 */

import type { Hit } from '~/types/api'

export function useSearch(options: { limit?: number; wait?: number } = {}) {
  const limit = options.limit ?? 40
  const wait = options.wait ?? 220

  const term = ref('')
  const hits = ref<Hit[]>([])
  const busy = ref(false)
  const failed = ref<string | null>(null)
  /** Whether an answer has actually come back for what is typed now. */
  const asked = ref(false)

  let waiting: ReturnType<typeof setTimeout> | undefined
  /**
   * Which request the answer on screen belongs to.
   *
   * "ко" can land after "кобра" and overwrite it. Counting the requests is
   * cheaper than cancelling them, and the loser is simply ignored.
   */
  let asking = 0

  async function run(query: string): Promise<void> {
    const mine = ++asking
    if (query.trim().length < 2) {
      hits.value = []
      asked.value = false
      busy.value = false
      return
    }
    busy.value = true
    failed.value = null
    try {
      const answer = await api.search(query.trim(), limit)
      if (mine !== asking) return
      hits.value = answer.items
      asked.value = true
    } catch (error) {
      if (mine !== asking) return
      failed.value = error instanceof ApiError ? error.message : 'Пошук не відповів'
    } finally {
      if (mine === asking) busy.value = false
    }
  }

  /** Types into it. The wait is what keeps a fast typist off the network. */
  function type(value: string): void {
    term.value = value
    clearTimeout(waiting)
    waiting = setTimeout(() => run(value), wait)
  }

  function clear(): void {
    clearTimeout(waiting)
    asking += 1
    term.value = ''
    hits.value = []
    asked.value = false
    busy.value = false
    failed.value = null
  }

  onBeforeUnmount(() => clearTimeout(waiting))

  return { term, hits, busy, failed, asked, type, run, clear }
}
