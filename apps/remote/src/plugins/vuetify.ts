/**
 * The Material layer, and the one theme it draws in.
 *
 * Dark only, and that is not a preference. This page opens from a camera
 * pointed at a television, which means a dim room — and a white card at that
 * moment is a flash in somebody's face. There is no toggle for the same reason
 * there is no navigation: the page exists for about thirty seconds.
 *
 * The colours are the launcher's, so the phone and the screen across the room
 * look like two halves of one thing rather than two products.
 */

import {
  mdiAlertCircleOutline,
  mdiCheckCircleOutline,
  mdiChevronDown,
  mdiClockOutline,
  mdiClose,
  mdiEye,
  mdiEyeOff,
  mdiTelevisionClassic,
} from '@mdi/js'
import { createVuetify } from 'vuetify'
import type { ThemeDefinition } from 'vuetify'
import { aliases, mdi } from 'vuetify/iconsets/mdi-svg'
import { uk } from 'vuetify/locale'

const nocturne: ThemeDefinition = {
  dark: true,
  colors: {
    background: '#0b0b10',
    surface: '#15151d',
    primary: '#8b7cf6',
    secondary: '#e06a8b',
    success: '#3fb950',
    warning: '#d29922',
    error: '#e5687f',
    info: '#8b7cf6',
  },
}

export const vuetify = createVuetify({
  // Path strings, not a webfont: a phone on a room's wi-fi should not wait on a
  // font file to find out what the button says.
  icons: {
    defaultSet: 'mdi',
    aliases: {
      ...aliases,
      mdiEye,
      mdiEyeOff,
      mdiTelevisionClassic,
      mdiCheckCircleOutline,
      mdiAlertCircleOutline,
      mdiClockOutline,
      mdiChevronDown,
      mdiClose,
    },
    sets: { mdi },
  },
  locale: { locale: 'uk', fallback: 'en', messages: { uk } },
  theme: { defaultTheme: 'nocturne', themes: { nocturne } },
  defaults: {
    // Flat cards with a hairline ring rather than Material's elevation: a
    // shadow is invisible on a dark surface, and the ring is not.
    VCard: { flat: true, border: true, rounded: 'lg' },
    VTextField: { variant: 'outlined', density: 'comfortable', hideDetails: 'auto' },
    VBtn: { variant: 'text' },
  },
})
