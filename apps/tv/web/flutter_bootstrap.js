{{flutter_js}}
{{flutter_build_config}}

// The boot screen in `index.html`, driven by what the loader is actually doing.
//
// Flutter's default bootstrap is one `_flutter.loader.load(…)` call. This is the
// same call with its milestones observed, because a cold start here is a 3.4 MB
// download and an engine to bring up — long enough that a blank ground reads as
// a broken page rather than as a slow one.
//
// **Every step is a fact.** The bar moves when the entrypoint has finished
// downloading, when the engine reports itself initialised, and when the app has
// actually run. Between those it creeps, slowly, toward the next real step and
// never past it: a bar that sits still for six seconds looks broken, and one
// that reaches 100% before the app does is a lie you notice.
(() => {
  const screen = document.getElementById('boot');
  const bar = document.getElementById('boot-bar');
  const what = document.getElementById('boot-what');

  /** Widens the bar to [percent] over [ms]. Interrupting one is what makes the
   *  creep give way the moment something real happens. */
  const reach = (percent, ms) => {
    if (!bar) return;
    bar.style.transitionDuration = `${ms}ms`;
    bar.style.width = `${percent}%`;
  };

  /** Somewhere to go while waiting, bounded by where the next fact will put it. */
  const creepTo = (percent, ms) => requestAnimationFrame(() => reach(percent, ms));

  const done = () => {
    if (!screen) return;
    reach(100, 300);
    if (what) what.textContent = 'ГОТОВО';
    // A frame for the app to paint into the ground the screen is already
    // showing, so the fade uncovers a picture rather than an empty page.
    requestAnimationFrame(() => {
      screen.classList.add('gone');
      screen.addEventListener('transitionend', () => screen.remove(), { once: true });
      // A screen left over because a transition never fired would sit on top of
      // the app forever, and it is `position: fixed`.
      setTimeout(() => screen.remove(), 1500);
    });
  };

  reach(6, 200);
  creepTo(60, 9000);

  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}},
    },
    onEntrypointLoaded: async (engineInitializer) => {
      // The download is over — the part that takes the time on a cold start.
      reach(76, 500);
      creepTo(92, 4000);

      const app = await engineInitializer.initializeEngine();
      reach(96, 400);

      await app.runApp();
      done();
    },
  });
})();
