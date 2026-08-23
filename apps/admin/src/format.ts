/**
 * How numbers and dates are written down.
 *
 * In one file because the alternative is each component reaching for
 * `toLocaleString` with slightly different options, and a dashboard where the
 * same count is punctuated two ways reads as two different measurements.
 */

const LOCALE = 'uk-UA'

const counts = new Intl.NumberFormat(LOCALE)
const percents = new Intl.NumberFormat(LOCALE, {
  style: 'percent',
  maximumFractionDigits: 1,
  signDisplay: 'exceptZero',
})
const shares = new Intl.NumberFormat(LOCALE, { style: 'percent', maximumFractionDigits: 1 })
const shortDate = new Intl.DateTimeFormat(LOCALE, { day: 'numeric', month: 'short' })
const fullDate = new Intl.DateTimeFormat(LOCALE, { day: 'numeric', month: 'long', year: 'numeric' })
const stamp = new Intl.DateTimeFormat(LOCALE, {
  day: 'numeric',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
})

export function count(value: number): string {
  return counts.format(value)
}

/** A signed percentage, for a delta. `null` has no honest rendering — see `Trend`. */
export function delta(change: number | null): string {
  return change === null ? '—' : percents.format(change)
}

export function share(part: number, whole: number): string {
  return whole === 0 ? '—' : shares.format(part / whole)
}

/**
 * A `YYYY-MM-DD` from the API, as a date.
 *
 * Parsed by hand rather than with `new Date('2026-08-23')`, which reads a bare
 * date as UTC midnight and then prints it in the reader's zone — so anybody
 * west of Greenwich sees every bar labelled with the day before.
 */
export function fromDay(day: string): Date {
  const [year, month, date] = day.split('-').map(Number)
  return new Date(year ?? 1970, (month ?? 1) - 1, date ?? 1)
}

export function dayShort(day: string): string {
  return shortDate.format(fromDay(day))
}

export function dayLong(day: string): string {
  return fullDate.format(fromDay(day))
}

/** An ISO instant, in the reader's own zone. */
export function moment(iso: string): string {
  return stamp.format(new Date(iso))
}

/** "3 години тому" — for a column where the exact minute is not the point. */
export function since(iso: string, now: number = Date.now()): string {
  const seconds = Math.round((now - new Date(iso).getTime()) / 1000)
  if (seconds < 90) return 'щойно'
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes} хв тому`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours} год тому`
  const days = Math.round(hours / 24)
  if (days < 30) return `${days} дн тому`
  return moment(iso)
}
