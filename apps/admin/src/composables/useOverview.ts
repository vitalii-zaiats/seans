/**
 * The dashboard's top half: totals, the daily series, the three breakdowns.
 *
 * One request, because the API answers all of it in one — a breakdown drawn
 * over a different stretch of time than the chart above it is a bug that looks
 * like data.
 */

import { ref, shallowRef, watch } from 'vue'

import { api } from '@/api/client'
import type { Overview } from '@/api/types'

import { useAuth } from './useAuth'

/** The presets in the range picker. Whole days, matching the API's windows. */
export const RANGES = [
  { days: 7, label: '7 днів' },
  { days: 30, label: '30 днів' },
  { days: 90, label: '90 днів' },
] as const

/** Rows per breakdown. Past this the tail is noise — the table below has it all. */
const TOP = 8

export function useOverview() {
  const auth = useAuth()

  const days = ref<number>(30)
  const activeDays = ref<number>(7)
  // `shallowRef`: the payload is replaced wholesale on every load and nothing
  // mutates it in place, so making a few hundred day objects reactive would be
  // work spent on notifications nobody subscribes to.
  const overview = shallowRef<Overview | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(false)

  async function load(): Promise<void> {
    const token = auth.token.value
    if (token === null) return

    loading.value = true
    error.value = null
    try {
      overview.value = await api.overview(token, {
        days: days.value,
        activeDays: activeDays.value,
        top: TOP,
      })
    } catch (cause) {
      auth.rejected(cause)
      error.value = cause instanceof Error ? cause.message : String(cause)
      // The old numbers stay on screen under the error. Blanking them would
      // mean a blink of "0 installs", which reads as a catastrophe rather than
      // as a failed refresh.
    } finally {
      loading.value = false
    }
  }

  // The window is the only input, so nothing else needs to remember to reload.
  watch([days, activeDays], () => void load())

  return { days, activeDays, overview, error, loading, load }
}
