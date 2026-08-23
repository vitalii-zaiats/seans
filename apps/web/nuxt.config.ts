// The web launcher: a Vue app with a router and nothing behind it.
//
// `ssr: false` on purpose. Nothing here needs a server — the API is the server,
// every screen is behind the same origin as it, and the two rails a viewer
// cares about most (what they were watching, what they saved) live in this
// browser's own storage and cannot be rendered anywhere else. A static bundle
// also means this ships the way `apps/admin` and `apps/remote` do: nginx, one
// image, no Node in production.
/** Where the API is while developing. 8000 is where `uv run api` listens. */
const API = process.env.API_PROXY ?? 'http://127.0.0.1:8000'

export default defineNuxtConfig({
  compatibilityDate: '2025-08-01',
  ssr: false,

  devtools: { enabled: false },

  css: ['~/assets/css/nocturne.css'],

  app: {
    head: {
      htmlAttrs: { lang: 'uk' },
      title: 'Сеанс',
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'color-scheme', content: 'dark' },
        { name: 'theme-color', content: '#161826' },
      ],
      /**
       * The stored theme, applied before the first paint.
       *
       * Inline and in the head on purpose: a bundle that set this on mount
       * would show one frame of the default palette first, and somebody who
       * chose the black ground would watch it flash blue-grey on every load.
       * The value *is* the colour, so this needs no table of names — see
       * `composables/useTheme.ts`.
       */
      script: [
        {
          innerHTML:
            'try{var r=document.documentElement,a=localStorage.getItem("theme.accent"),' +
            'g=localStorage.getItem("theme.ground");' +
            'if(a)r.style.setProperty("--accent",a);' +
            'if(g)r.style.setProperty("--ground",g)}catch(e){}',
          tagPosition: 'head',
        },
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href:
            'https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;700' +
            '&family=Karla:wght@400;500;700&family=JetBrains+Mono:wght@400;500&display=swap',
        },
      ],
    },
  },

  // The API is same-origin in production — nginx puts the two behind one
  // address, exactly as it does for the dashboard. In dev it is a separate
  // process, and this is what makes them look like one origin: no CORS to
  // arrange and no base URL to configure.
  //
  // Three entries rather than one per feature: the whole JSON API lives under
  // `/api/`, and the two relays sit at the root because their addresses end up
  // inside an `.m3u8` and inside a browser's cache — see `api.versions`.
  nitro: {
    devProxy: {
      '/api': { target: `${API}/api`, changeOrigin: true },
      '/proxy': { target: `${API}/proxy`, changeOrigin: true },
      '/stream': { target: `${API}/stream`, changeOrigin: true },
    },
  },

  runtimeConfig: {
    public: {
      /**
       * Where the television app's own web build is served.
       *
       * Only the downloads page uses it, and only as a link. `8083` is what
       * `compose.yaml` publishes the `tv` image on; a deployment sets
       * `NUXT_PUBLIC_TV_URL` at build time, because a static bundle has no
       * server to read an environment variable at run time.
       */
      tvUrl: process.env.NUXT_PUBLIC_TV_URL ?? 'http://localhost:8083',
    },
  },

  typescript: { typeCheck: false, strict: true },
})
