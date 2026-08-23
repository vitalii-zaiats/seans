/**
 * The Material layer, and the two themes it draws in.
 *
 * The colours here are the *interface's* — chosen to sit behind text and to
 * pass contrast on a control. They are not the chart palette, which is chosen
 * so two adjacent marks stay apart for a reader who cannot tell red from green,
 * and which lives in `styles/tokens.scss`. The two agree on their surfaces on
 * purpose: a card and the chart inside it must be the same colour.
 */

import { createVuetify } from 'vuetify'
import type { ThemeDefinition } from 'vuetify'
import { aliases, mdi } from 'vuetify/iconsets/mdi-svg'
import { uk } from 'vuetify/locale'


const THEME_KEY = 'super-movies.admin.theme'

const light: ThemeDefinition = {
  dark: false,
  colors: {
    background: '#f9f9f7',
    surface: '#fcfcfb',
    primary: '#2a78d6',
    secondary: '#eb6834',
    success: '#0ca30c',
    warning: '#fab219',
    error: '#d03b3b',
    info: '#2a78d6',
  },
}

const dark: ThemeDefinition = {
  dark: true,
  colors: {
    background: '#0d0d0d',
    surface: '#1a1a19',
    primary: '#3987e5',
    secondary: '#d95926',
    success: '#0ca30c',
    warning: '#fab219',
    error: '#e66767',
    info: '#3987e5',
  },
}

/** What the reader picked last, or what their system says. */
function preferred(): 'light' | 'dark' {
  try {
    const saved = localStorage.getItem(THEME_KEY)
    if (saved === 'light' || saved === 'dark') return saved
  } catch {
    /* storage off — fall through to the system's answer */
  }
  return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export function rememberTheme(name: string): void {
  try {
    localStorage.setItem(THEME_KEY, name)
  } catch {
    /* the choice holds for this tab either way */
  }
}

export const vuetify = createVuetify({
  // Path strings, not a webfont — see `icons.ts`. `aliases` carries the ones
  // Vuetify draws itself: the select's chevron, the table's sort arrow, the
  // clear button on a search box.
  icons: { defaultSet: 'mdi', aliases, sets: { mdi } },
  // The data table writes its own footer — "рядків на сторінці", the range,
  // the next-page label a screen reader reads out. Without this they arrive
  // in English in the middle of a Ukrainian screen.
  locale: { locale: 'uk', fallback: 'en', messages: { uk } },
  theme: {
    defaultTheme: preferred(),
    themes: { light, dark },
  },
  defaults: {
    // Flat cards with a hairline ring rather than Material's default elevation:
    // eight raised rectangles on one screen is a lot of shadow, and the ring
    // survives dark mode, where a shadow is invisible.
    VCard: { flat: true, border: true, rounded: 'lg' },
    VTextField: { variant: 'outlined', density: 'comfortable', hideDetails: 'auto' },
    VSelect: { variant: 'outlined', density: 'comfortable', hideDetails: 'auto' },
    VBtn: { variant: 'text' },
  },
})
