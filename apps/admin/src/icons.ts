/**
 * The dozen icons this dashboard draws.
 *
 * Named imports from `@mdi/js` rather than the icon *font*: the font ships
 * seven thousand glyphs and a stylesheet naming every one of them, which came
 * to about 700 kB for the twelve used here. These are tree-shaken path strings.
 *
 * The cost is that an icon has to be imported before it can be used — which is
 * the same rule as every other symbol in the app.
 */
export {
  mdiArrowBottomRight,
  mdiArrowTopRight,
  mdiChartLine,
  mdiEye,
  mdiEyeOff,
  mdiLogout,
  mdiMagnify,
  mdiMinus,
  mdiRefresh,
  mdiTable,
  mdiWeatherNight,
  mdiWeatherSunny,
} from '@mdi/js'
