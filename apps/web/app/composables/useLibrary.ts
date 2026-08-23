/**
 * The two lists the API does not keep: what is half-watched, and what was
 * saved for later.
 *
 * The same two the television keeps in `apps/tv/lib/data/library_store.dart`,
 * under the same two keys and with the same rules — a stop in the last few
 * minutes is a finish rather than a pause, and the first minute is not a
 * resume. Kept here rather than on the server because the server has no
 * endpoint for either: there is no watch history in `contracts/openapi.json`,
 * and inventing one on the client would be a promise this app cannot keep.
 *
 * `localStorage` rather than a cookie: nothing here is ever sent anywhere.
 */

/** Where somebody got to in something. */
export interface WatchProgress {
  slug: string
  /** Milliseconds, both of them — what `HTMLMediaElement` counts in, near enough. */
  position: number
  duration: number
  updatedAt: number
  /** Where in a series this was, when it is one. */
  season?: number | null
  episode?: number | null
}

const PROGRESS_KEY = 'watch.progress'
const LIST_KEY = 'watch.list'

/**
 * How many half-watched titles are kept. The rail shows a handful, and an
 * unbounded list is only slower to read on every boot.
 */
const MAX_PROGRESS = 20

/** 0–1. Zero when the duration is not known yet. */
export function fractionOf(progress: WatchProgress): number {
  if (!progress.duration) return 0
  return Math.min(1, Math.max(0, progress.position / progress.duration))
}

/**
 * Whether this is close enough to the end to count as watched.
 *
 * The last few minutes of a film are credits, so a stop there is a finish, not
 * a pause — and "Продовжити дивитись" should not offer it back.
 */
export function isFinished(progress: WatchProgress): boolean {
  return fractionOf(progress) >= 0.94
}

/** Whether it is far enough in to be worth resuming at all. */
export function isStarted(progress: WatchProgress): boolean {
  return progress.position > 60_000 && !isFinished(progress)
}

function read<T>(key: string, fallback: T): T {
  if (!import.meta.client) return fallback
  try {
    const raw = window.localStorage.getItem(key)
    return raw ? (JSON.parse(raw) as T) : fallback
  } catch {
    // Storage a browser refuses (private mode, a wiped profile) or a value
    // written by an older shape. Either way the lists start empty rather than
    // taking the whole app down with them.
    return fallback
  }
}

function write(key: string, value: unknown): void {
  if (!import.meta.client) return
  try {
    window.localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // A full or forbidden store. Losing a bookmark is not worth an error on
    // screen in the middle of a film.
  }
}

export function useLibrary() {
  // `useState` rather than a module-level ref: every screen that shows the list
  // is looking at the same array, so saving from the title page changes the
  // header's count without either knowing about the other.
  const progress = useState<WatchProgress[]>('library.progress', () =>
    read<WatchProgress[]>(PROGRESS_KEY, []),
  )
  const list = useState<string[]>('library.list', () => read<string[]>(LIST_KEY, []))

  /** Half-watched titles, most recent first, finished ones dropped. */
  const resumable = computed(() =>
    [...progress.value].filter(isStarted).sort((a, b) => b.updatedAt - a.updatedAt),
  )

  function progressFor(slug: string): WatchProgress | null {
    return progress.value.find((one) => one.slug === slug) ?? null
  }

  /** Remembers where a title was stopped, replacing whatever was there before. */
  function remember(entry: Omit<WatchProgress, 'updatedAt'>): void {
    const next = [
      { ...entry, updatedAt: Date.now() },
      ...progress.value.filter((one) => one.slug !== entry.slug),
    ].slice(0, MAX_PROGRESS)
    progress.value = next
    write(PROGRESS_KEY, next)
  }

  /** Takes a title out of "Продовжити дивитись" — what finishing one does. */
  function forget(slug: string): void {
    progress.value = progress.value.filter((one) => one.slug !== slug)
    write(PROGRESS_KEY, progress.value)
  }

  function isSaved(slug: string): boolean {
    return list.value.includes(slug)
  }

  /** Adds or removes, and answers with what it now is. */
  function toggleSaved(slug: string): boolean {
    const saved = isSaved(slug)
    list.value = saved ? list.value.filter((one) => one !== slug) : [slug, ...list.value]
    write(LIST_KEY, list.value)
    return !saved
  }

  return { progress, list, resumable, progressFor, remember, forget, isSaved, toggleSaved }
}
