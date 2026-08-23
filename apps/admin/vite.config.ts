import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import vuetify from 'vite-plugin-vuetify'

const shared = fileURLToPath(new URL('./src/styles/_shared.scss', import.meta.url))

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
    // `autoImport` is what keeps a Material component library from costing what
    // one usually costs: components are pulled in per use, so the bundle holds
    // the dozen this dashboard draws rather than the whole set.
    vuetify({ autoImport: true, styles: { configFile: 'src/styles/settings.scss' } }),
  ],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  css: {
    preprocessorOptions: {
      // Mixins and variables only — this is prepended to every style block, so
      // anything emitting CSS here would be emitted once per component.
      scss: { additionalData: `@use "${shared}" as *;\n` },
    },
  },
  server: {
    // The API is same-origin in production, so the client asks for `/admin/...`
    // with no host at all. In dev it is a separate process, and this is what
    // makes the two look like one origin — no CORS, no base URL to configure.
    proxy: { '/api': API },
  },
})
