import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import vuetify from 'vite-plugin-vuetify'

// Where the local API is listening. Overridable because 8000 is a popular port
// and a second copy of the stack on one machine should not mean editing a file
// that is checked in.
const API = process.env.API_PROXY ?? 'http://127.0.0.1:8000'

// Where this app is mounted.
//
// `/` on its own port, which is how `compose.yaml` runs it. Behind the single
// front door in `compose.edge.yaml` it is not: every app there shares one
// origin, so each needs a prefix of its own, and every asset URL the build
// writes into `index.html` has to carry it. Vite bakes this in at build time —
// hence a build arg rather than an environment variable at run time.
const BASE = process.env.APP_BASE ?? '/'

export default defineConfig({
  base: BASE,
  plugins: [
    vue(),
    // Components pulled in per use, so a Material library costs the handful of
    // controls this page draws rather than the whole set. It matters more here
    // than on the dashboard: this page opens on a phone, from a camera, on
    // whatever connection the room has.
    vuetify({ autoImport: true }),
  ],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    // The API is same-origin in production, so the client asks for `/auth/...`
    // with no host at all. In dev it is a separate process, and this is what
    // makes the two look like one origin — no CORS, no base URL to configure.
    proxy: { '/api/v1/auth': API },
  },
})
