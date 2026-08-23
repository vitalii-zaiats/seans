# web

Сеанс — the catalogue in a browser: the television's launcher without the
television.

**The brand is `SEANS`; `kinostrain` is somebody else's.** The wordmark in the
bar and the name in every `<title>` are ours. The catalogue upstream is not: the
API this talks to proxies kinostrain.com, and the client that reads it keeps
that name because it *is* that service. Nothing in this app should carry it.

Nuxt 4 and TypeScript, talking to the same REST API as `apps/tv`
(`contracts/openapi.json`), drawn in the Nocturne palette the Flutter app
carries and laid out the way the *Ambient Web* board in the design archive lays
it out — a sticky blurred bar, one enormous hero, rails under it, a grid at the
bottom, and a full-screen player over everything.

## What it is not

- **No setup wizard.** First run on a box has to decide what the box carries;
  a browser carries whatever the address bar points at.
- **No live television, no installed apps, no local network.** Those are the
  machine, and this is not one.
- **No stream yet.** The player is a working picture of a player: the controls,
  the keys, the timecode and the resume it writes down are real, the video is
  the title's artwork, and it says so at the foot of the screen. Playing for
  real needs a server that is not a browser — the catalogue hands out embed
  pages rather than `.m3u8`s, and `Referer`, `Origin` and `User-Agent` cannot be
  set from inside a page. `packages/dart/cors_proxy` is what the Flutter web
  build talks to for exactly this, and porting it to a Nitro route is the next
  piece of work here.

## Running it

```bash
npm install
npm run dev          # localhost:3000, proxying the API at 127.0.0.1:8000
API_PROXY=http://127.0.0.1:8001 npm run dev   # ...somewhere else
```

The API has to be up — `uv run api` from the repository root, or
`docker compose up api`. Nothing in this app has a base URL: it asks for
`/catalogue/…` with no host, and the dev proxy (`nuxt.config.ts`) or nginx
(`nginx.conf.template`) puts the two behind one address.

```bash
npm run build        # static bundle in .output/public
npx nuxi typecheck   # what the image runs before it builds
```

## Where things are

```
app/
  assets/css/nocturne.css   the design system's tokens, and every shared class
  components/               the bar, the hero, a rail, a card, the player
  composables/              the account, the two local lists, the player
  pages/                    /, /catalog/:type, /title/:slug, /search, /list,
                            /downloads, /account
  types/api.ts              the wire, mirroring contracts/openapi.json
  utils/                    the API client, and the formatting the design needs
```

## The downloads page

`/downloads` offers the two builds that are not this one: the Android TV APK and
the television app's own web build, which installs as a PWA. Neither version
number nor link is typed into the page — it asks `POST /init` **without an
install id**, which answers with the update plan and writes nothing down. Point
it at the right web build with `NUXT_PUBLIC_TV_URL` at build time; the default
is `http://localhost:8083`, where `compose.yaml` publishes the `tv` image.

## Two things worth knowing before you trip over them

- **"Мій список" and "Продовжити дивитись" are this browser's.** There is no
  watch history in the API — look at `contracts/openapi.json` and there is
  nothing to store one in — so both live in `localStorage`, under the same two
  keys and the same rules as `apps/tv/lib/data/library_store.dart`. Signing in
  does not move them, and the empty state says so.
- **Every poster comes through the API.** The catalogue's own host sends no CORS
  header, so the API rewrites each artwork URL to a `/proxy/…` path of its own.
  That is why `nginx.conf.template` proxies `/proxy/` as well, and why a
  deployment that forgets it loads a site with no pictures in it.
