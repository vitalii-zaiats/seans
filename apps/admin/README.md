# admin

The dashboard for whoever runs this: how many copies of the app are out there,
where they are running, and which of them are still being opened.

Vue 3 + TypeScript + SCSS, with [Vuetify](https://vuetifyjs.com) for the
Material components. No router and no store — there is one screen behind a login
and one session per tab, and both would be more machinery than the thing they
hold.

```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck, then dist/
npm run typecheck
```

## It needs an API, and an admin to log in as

Every endpoint it reads is behind the `Admin` role, so there has to be an
administrator before there is anything to see. The role cannot be granted over
HTTP by somebody who does not already have it, which leaves the first one with
no way in — hence the shell command:

```bash
cd ../api
uv run api admin you@example.com     # creates it, or promotes an account that exists
```

In development the API is a second process, and `vite.config.ts` proxies
`/api/` to it so the two look like one origin — no CORS, and no
base URL to configure:

```bash
cd ../api && uv run api             # 127.0.0.1:8000
API_PROXY=http://127.0.0.1:8010 npm run dev    # when 8000 is taken
```

In production the API answers on the same origin as this bundle, so nothing is
configured at all. `VITE_API_URL` is there for the deployment where it does not
— see `.env.example`.

## What is where

```
src/
  api/          the wire: `types.ts` mirrors the API's schemas, `client.ts` is
                the only place that knows about the bearer header
  composables/  session, overview, table — module-level refs, no store
  components/   the cards the dashboard is made of
  views/        the one screen
  styles/       Vuetify's SASS settings, and the chart palette
```

## Two palettes, on purpose

`styles/tokens.scss` is not the Vuetify theme and is not derived from it. A UI
colour is picked to sit behind text; a series colour is picked so two adjacent
marks stay apart for a reader who cannot tell red from green — the two lines on
the chart clear a CVD ΔE of 24.7 against each other, which no amount of
"looks different enough" would have guaranteed. Both are validated against the
surface they are actually drawn on, which is why the dark values are their own
steps rather than the light ones lightened.

## The chart is hand-written SVG

Two lines, a grid and a crosshair, in `components/InstallsChart.vue`. A chart
library would have arrived with its own colours, its own tooltip and its own
theme to keep in step with Vuetify's. Both series count the same thing, so they
share one axis — a second scale on the right would let the lines cross wherever
the scales happened to put them, which is a correlation the data does not have.

The card has a table toggle in its corner. That is the accessible reading of the
same numbers, not a nicety.
