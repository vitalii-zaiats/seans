/**
 * One code, from the moment the page opens to the moment it is spent.
 *
 * The countdown is the reason this is a composable rather than three refs in a
 * component: a code lives about ten minutes, and a page that shows a stale
 * number is a page that lets somebody sit there waiting for a button that will
 * refuse them.
 */

import { computed, onScopeDispose, ref } from 'vue'

import { ApiError, api } from '@/api/client'
import type { DeviceLink } from '@/api/types'

/** Where the page stands. Each of these is a different thing to say. */
export type Stage =
  | 'loading'
  /** Waiting for somebody to press the button. */
  | 'waiting'
  /** Approved by this phone, just now. */
  | 'approved'
  /** No such code: expired long ago, mistyped, or already finished with. */
  | 'missing'
  /** It ran out while the page was open. */
  | 'expired'
  /** Somebody else approved it first. */
  | 'taken'
  /** Something else went wrong, and [error] says what. */
  | 'failed'

export function usePairing(code: string) {
  const link = ref<DeviceLink | null>(null)
  const stage = ref<Stage>('loading')
  const error = ref<string | null>(null)
  const busy = ref(false)
  const seconds = ref(0)

  let ticker: ReturnType<typeof setInterval> | null = null

  function stopTicking(): void {
    if (ticker !== null) clearInterval(ticker)
    ticker = null
  }

  function startTicking(from: number): void {
    stopTicking()
    seconds.value = from
    ticker = setInterval(() => {
      seconds.value = Math.max(0, seconds.value - 1)
      if (seconds.value === 0) {
        stopTicking()
        // Only while nobody has finished with it. An approval that landed a
        // second before the clock ran out still counts.
        if (stage.value === 'waiting') stage.value = 'expired'
      }
    }, 1000)
  }

  /** Turn a refusal into the one sentence that fits it. */
  function settle(failure: unknown): void {
    stopTicking()
    if (failure instanceof ApiError) {
      if (failure.missing) return void (stage.value = 'missing')
      if (failure.taken) return void (stage.value = 'taken')
      if (failure.invalid) return void (stage.value = 'expired')
      error.value = failure.message
    } else {
      error.value = 'Щось пішло не так'
    }
    stage.value = 'failed'
  }

  async function load(): Promise<void> {
    stage.value = 'loading'
    error.value = null
    try {
      const found = await api.link(code)
      link.value = found
      if (found.expires_in <= 0) {
        stage.value = 'expired'
        return
      }
      // Already approved, and not by this page — the box is collecting its
      // session right now and there is nothing left to do here.
      stage.value = found.approved ? 'approved' : 'waiting'
      startTicking(found.expires_in)
    } catch (failure) {
      settle(failure)
    }
  }

  async function approve(token: string): Promise<void> {
    busy.value = true
    error.value = null
    try {
      link.value = await api.approve(code, token)
      stage.value = 'approved'
      stopTicking()
    } catch (failure) {
      settle(failure)
    } finally {
      busy.value = false
    }
  }

  onScopeDispose(stopTicking)

  return {
    link,
    stage,
    error,
    busy,
    seconds,
    /** `9:41`, which is how long is left rather than how long there was. */
    countdown: computed(() => {
      const left = seconds.value
      return `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`
    }),
    load,
    approve,
  }
}
