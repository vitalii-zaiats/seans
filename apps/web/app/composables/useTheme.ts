/**
 * The two colours the whole interface is built from.
 *
 * The same palette the television offers in `apps/tv/lib/theme/nocturne.dart`,
 * spelled out again rather than shared — the two sides agree on a vocabulary
 * independently, which is the rule the API's own modules follow, and a hue
 * renamed on one side then shows up as a mismatch instead of leaking through.
 *
 * Only `--accent` and `--ground` are ever set. Everything else — panels, tints,
 * the lifted accent for paragraph text — is mixed from those two in
 * `assets/css/nocturne.css`, so a theme is two values rather than a stylesheet.
 */

export interface PaletteOption {
  label: string
  /** The value itself is what is stored, so there is no id table to keep in step. */
  color: string
}

/**
 * Every one is a mid-chroma hue that keeps at least 3:1 against the dark
 * grounds — enough for a ring, a glow and interface chrome, which is all the
 * accent is ever used for.
 */
export const ACCENTS: readonly PaletteOption[] = [
  { label: 'Бузковий', color: '#9184d9' },
  { label: 'Бірюзовий', color: '#4fb3a7' },
  { label: 'Бурштиновий', color: '#d9a441' },
  { label: 'Трояндовий', color: '#d9738a' },
  { label: 'Небесний', color: '#5b9bd9' },
  { label: 'Лаймовий', color: '#8fbf52' },
]

export const GROUNDS: readonly PaletteOption[] = [
  { label: 'Ноктюрн', color: '#161826' },
  { label: 'Опівніч', color: '#0e1013' },
  { label: 'Чорнило', color: '#000000' },
  { label: 'Індиго', color: '#1a1b2e' },
]

const ACCENT_KEY = 'theme.accent'
const GROUND_KEY = 'theme.ground'

function read(key: string, fallback: string): string {
  if (!import.meta.client) return fallback
  try {
    return window.localStorage.getItem(key) ?? fallback
  } catch {
    return fallback
  }
}

export function useTheme() {
  const accent = useState('theme.accent', () => read(ACCENT_KEY, ACCENTS[0]!.color))
  const ground = useState('theme.ground', () => read(GROUND_KEY, GROUNDS[0]!.color))

  function paint(): void {
    if (!import.meta.client) return
    const root = document.documentElement
    root.style.setProperty('--accent', accent.value)
    root.style.setProperty('--ground', ground.value)
    // The browser paints its own chrome from this on a phone, and a bar in
    // last week's colour over this week's page is the sort of seam nobody can
    // name but everybody sees.
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', ground.value)
  }

  function keep(key: string, value: string): void {
    try {
      window.localStorage.setItem(key, value)
    } catch {
      // Then the choice lasts this visit, which is better than refusing to
      // make it.
    }
  }

  function chooseAccent(color: string): void {
    accent.value = color
    keep(ACCENT_KEY, color)
    paint()
  }

  function chooseGround(color: string): void {
    ground.value = color
    keep(GROUND_KEY, color)
    paint()
  }

  return { accent, ground, chooseAccent, chooseGround, paint }
}
