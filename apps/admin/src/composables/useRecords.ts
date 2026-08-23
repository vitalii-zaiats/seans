/**
 * The table under the charts.
 *
 * Paged and searched separately from the overview on purpose: re-measuring a
 * month of aggregates on every keystroke is the obvious way to build a
 * dashboard nobody leaves open.
 */

import { ref, shallowRef, watch } from 'vue'

import { api } from '@/api/client'
import type { InstallRecord, Platform } from '@/api/types'

import { useAuth } from './useAuth'

/** Long enough that the API's own ceiling (200) is never the binding one. */
const TYPING_PAUSE_MS = 300

export function useRecords() {
  const auth = useAuth()

  const page = ref(1)
  const perPage = ref(25)
  const platform = ref<Platform | null>(null)
  const search = ref('')

  const items = shallowRef<InstallRecord[]>([])
  const total = ref(0)
  const error = ref<string | null>(null)
  const loading = ref(false)

  async function load(): Promise<void> {
    const token = auth.token.value
    if (token === null) return

    loading.value = true
    error.value = null
    try {
      const answer = await api.records(token, {
        limit: perPage.value,
        offset: (page.value - 1) * perPage.value,
        platform: platform.value,
        search: search.value,
      })
      items.value = answer.items
      total.value = answer.total
    } catch (cause) {
      auth.rejected(cause)
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  watch([page, perPage], () => void load())

  // Narrowing the set changes what page 1 even means, so both filters send the
  // reader back to it. Setting `page` to 1 when it already is 1 fires no watcher,
  // hence the explicit load.
  watch([platform, search], () => {
    if (page.value === 1) void load()
    else page.value = 1
  })

  /** A search box that asked the server per keystroke would ask six times a word. */
  let pending: ReturnType<typeof setTimeout> | undefined
  function searchLater(term: string): void {
    clearTimeout(pending)
    pending = setTimeout(() => {
      search.value = term
    }, TYPING_PAUSE_MS)
  }

  return { page, perPage, platform, search, items, total, error, loading, load, searchLater }
}
