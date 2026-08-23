/**
 * Turning what the API says into what the design shows.
 *
 * The section names are the television's — `HomeRailId` in
 * `apps/tv/lib/core/home_rails.dart` — spelled out again rather than shared,
 * which is the same rule the API's own modules follow: two sides that agree on
 * a vocabulary independently show a rename as a mismatch at the seam instead of
 * leaking it through to the wire.
 */

import type { Genre, ContentType } from '~/types/api'

/**
 * The fields a meta line is built from.
 *
 * A card and a title's details are two shapes of the same thing, and the
 * difference between them is exactly one field: a card arrives with its years
 * already written out, and details arrive with the two numbers. Naming what is
 * needed rather than taking one of the two means neither has to be converted
 * into the other to get a line of text out of it.
 */
export interface MetaLike {
  genres: Genre[]
  year_label?: string | null
  year_start?: number | null
  year_end?: number | null
  time?: string | null
  imdb_mark?: number | null
}

const SECTIONS: Record<ContentType, string> = {
  movie: 'Фільми',
  serial: 'Серіали',
  'cartoon-movie': 'Мультфільми',
  'cartoon-series': 'Мультсеріали',
  anime: 'Аніме',
}

/** What a section is called. An unknown one keeps whatever upstream called it. */
export function sectionName(type: ContentType | null, fallback = 'Каталог'): string {
  return type ? SECTIONS[type] : fallback
}

/**
 * The years, however they arrived.
 *
 * `year_label` is assembled by the API for a card — `2019 – …` for a series
 * still running. Details carry the numbers instead, and this writes the same
 * label from them rather than making the screen choose.
 */
export function yearLabel(subject: MetaLike): string | null {
  if (subject.year_label) return subject.year_label
  if (!subject.year_start) return null
  if (!subject.year_end) return `${subject.year_start}`
  if (subject.year_end === subject.year_start) return `${subject.year_start}`
  return `${subject.year_start} – ${subject.year_end}`
}

/** The one-line meta under a title: genre, year, rating — whichever exist. */
export function cardMeta(subject: MetaLike): string {
  const parts: string[] = []
  const genre = subject.genres[0]?.name
  if (genre) parts.push(genre)
  const years = yearLabel(subject)
  if (years) parts.push(years)
  if (subject.imdb_mark) parts.push(`★ ${subject.imdb_mark.toFixed(1)}`)
  return parts.join(' · ')
}

/** The same, in the capitalised mono the hero wears. */
export function heroMeta(subject: MetaLike): string {
  const parts: string[] = []
  const genre = subject.genres[0]?.name
  if (genre) parts.push(genre.toUpperCase())
  const years = yearLabel(subject)
  if (years) parts.push(years)
  if (subject.time) parts.push(subject.time)
  if (subject.imdb_mark) parts.push(`★ ${subject.imdb_mark.toFixed(1)}`)
  return parts.join(' · ')
}

/**
 * A hue for a title, from its slug.
 *
 * Artwork is missing often enough — a title upstream never filled in, a proxy
 * that answered 502 — that a single grey placeholder would turn a rail into one
 * long smear. A hash of the slug gives each its own colour, the same one every
 * time, and the gradient underneath the poster is what the Ambient board draws
 * where a photograph would go.
 */
export function hueOf(slug: string): number {
  let hash = 0
  for (let i = 0; i < slug.length; i += 1) {
    hash = (hash * 31 + slug.charCodeAt(i)) % 360
  }
  return hash
}

/** The placeholder itself: three light sources in OKLCH, as the board has it. */
export function artBackground(slug: string): string {
  const h = hueOf(slug)
  return (
    `radial-gradient(ellipse at 72% 18%, oklch(0.42 0.09 ${h}) 0%, transparent 55%), ` +
    `radial-gradient(ellipse at 18% 84%, oklch(0.28 0.07 ${(h + 50) % 360}) 0%, transparent 60%), ` +
    `linear-gradient(115deg, oklch(0.22 0.05 ${h}) 0%, oklch(0.14 0.03 ${(h + 35) % 360}) 60%, ` +
    `oklch(0.11 0.02 ${(h + 70) % 360}) 100%)`
  )
}

/** `1:04:12`, or `04:12` for anything under an hour. Milliseconds in. */
export function timecode(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  const pad = (value: number) => String(value).padStart(2, '0')
  return hours ? `${hours}:${pad(minutes)}:${pad(seconds)}` : `${pad(minutes)}:${pad(seconds)}`
}

/**
 * A guess at how long something runs, in milliseconds.
 *
 * The API carries `time` as a localised sentence — `1 год 50 хв` — because that
 * is what upstream sends; there is no machine-readable duration anywhere in the
 * contract. The player needs a number for its progress bar, so this reads the
 * digits back out, and falls back to an hour and a half when there is nothing
 * to read.
 */
export function runtimeMs(time: string | null | undefined): number {
  if (!time) return 90 * 60_000
  const hours = /(\d+)\s*год/.exec(time)
  const minutes = /(\d+)\s*хв/.exec(time)
  const total = Number(hours?.[1] ?? 0) * 60 + Number(minutes?.[1] ?? 0)
  return (total || 90) * 60_000
}
