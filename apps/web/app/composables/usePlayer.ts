/**
 * Opening a title, and writing down where it got to.
 *
 * The opening is three steps rather than one, and they are all the catalogue's
 * doing: it hands out an *embed page*, not a stream. So this fetches the title's
 * players if it does not have them, asks the API to read one for its `.m3u8`
 * (`POST /playback/resolve` — a browser cannot: no CORS header, and a `Referer`
 * it is not allowed to set), and then plays that through `/stream`, which is the
 * only address a browser is allowed to read the playlist from.
 *
 * Each step can fail differently and the screen says which: a title nobody has
 * uploaded is not the same as a player page that would not open.
 */

import type { Card, Details, Season, TvChannel } from '~/types/api'

export interface Playing {
  slug: string
  title: string
  meta: string
  art: string | null
  /** Null while the stream is still being worked out. */
  src: string | null
  /** Where to pick up, in seconds — what `<video>` counts in. */
  startAt: number
  season: number | null
  episode: number | null
  /** What went wrong, if anything did. */
  failed: string | null
  /**
   * Live television, where there is no "where you got to".
   *
   * A channel has no end and no position worth keeping: a bookmark on it would
   * mean "resume at 14:32 yesterday", which is not a thing anybody can do.
   */
  live: boolean
}

/** The embed pages of one season, or of one episode of it. */
function linksIn(season: Season, episode: number | null): string[] {
  const byProvider = episode
    ? (season.episode_players[String(episode)] ?? {})
    : season.player_data
  return Object.values(byProvider)
    .flat()
    .map((source) => source.link)
}

export function usePlayer() {
  const playing = useState<Playing | null>('player.playing', () => null)
  const library = useLibrary()

  /**
   * Opens a title.
   *
   * Takes a card *or* the full details: the home screen has only a card, and
   * fetching the rest is this function's business rather than every caller's.
   */
  async function play(
    subject: Card | Details,
    options: { season?: number | null; episode?: number | null; from?: number } = {},
  ): Promise<void> {
    const previous = library.progressFor(subject.slug)
    const at = options.from ?? previous?.position ?? 0

    playing.value = {
      slug: subject.slug,
      title: subject.name,
      meta: heroMeta(subject),
      art: subject.slider_url ?? subject.poster_url,
      src: null,
      // Milliseconds on the way in — that is what the library keeps — and
      // seconds from here on, because that is what a `<video>` counts in.
      startAt: at / 1000,
      season: options.season ?? previous?.season ?? null,
      episode: options.episode ?? previous?.episode ?? null,
      failed: null,
      live: false,
    }

    try {
      const details = 'seasons' in subject ? subject : await api.content(subject.slug)
      const wanted = playing.value.season
      const season =
        details.seasons.find((one) => one.number === wanted) ??
        details.seasons.find((one) => one.is_loaded) ??
        details.seasons[0]

      if (!season) throw new ApiError(404, 'Цей тайтл поки що ні на чому дивитись')

      // Only ashdi's player is understood on the server side. Another
      // provider's embed is a different page with a different configuration,
      // and guessing at it fails in a way that looks like a broken title.
      const link = linksIn(season, playing.value.episode).find((one) => one.includes('ashdi'))
      if (!link) throw new ApiError(404, 'Для цього тайтла немає плеєра, який ми вміємо читати')

      const resolved = await api.resolve(link, {
        season: season.is_episodic ? null : season.number,
        episode: season.is_episodic ? null : playing.value.episode,
      })

      const best = resolved.streams[0]
      if (!best) throw new ApiError(404, 'Плеєр відкрився, але потоку в ньому немає')

      // The title may have been closed while all that was in flight.
      if (playing.value?.slug !== subject.slug) return
      playing.value = { ...playing.value, src: api.streamed(best.url) }
    } catch (error) {
      if (playing.value?.slug !== subject.slug) return
      playing.value = {
        ...playing.value,
        failed: error instanceof ApiError ? error.message : 'Не вдалося відкрити',
      }
    }
  }

  /**
   * Opens a channel.
   *
   * One request rather than the film's two: a channel's lease already carries a
   * playable address, and asking for it with `use_proxy` is what makes it
   * readable from a page at all.
   */
  async function playChannel(channel: TvChannel): Promise<void> {
    const slug = `tv-${channel.id}`
    playing.value = {
      slug,
      title: channel.name,
      meta: channel.now_playing ?? 'ПРЯМИЙ ЕФІР',
      art: channel.banner_url ?? channel.icon_url,
      src: null,
      startAt: 0,
      season: null,
      episode: null,
      failed: null,
      live: true,
    }

    try {
      const lease = await api.openChannel(channel.id)
      if (playing.value?.slug !== slug) return
      // Never `plain_url` here: that address exists because Android rejects the
      // stitching host's certificate chain, and a page served over https cannot
      // load plain http at all.
      playing.value = { ...playing.value, src: lease.url }
    } catch (error) {
      if (playing.value?.slug !== slug) return
      playing.value = {
        ...playing.value,
        failed: error instanceof ApiError ? error.message : 'Канал не відкрився',
      }
    }
  }

  /** Where the playhead is, in milliseconds, as the library keeps it. */
  function remember(position: number, duration: number): void {
    const current = playing.value
    if (!current || current.live || duration <= 0) return

    const entry = {
      slug: current.slug,
      position: position * 1000,
      duration: duration * 1000,
      season: current.season,
      episode: current.episode,
    }

    // A stop in the last few minutes is a finish, not a pause, and
    // "Продовжити дивитись" should not offer it back. The rule lives in
    // `useLibrary`, so the television and this agree on it.
    if (isFinished({ ...entry, updatedAt: Date.now() })) {
      library.forget(current.slug)
      return
    }
    library.remember(entry)
  }

  function close(): void {
    playing.value = null
  }

  return { playing, play, playChannel, remember, close }
}
