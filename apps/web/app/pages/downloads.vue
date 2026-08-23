<script setup lang="ts">
/**
 * Where to get the app that is not this one.
 *
 * Two of them, and they are the same program: the launcher that replaces a
 * box's home screen, and that same Flutter build compiled for a browser and
 * installable as a PWA. This site is the third thing — a catalogue you can read
 * without installing anything — and says so at the bottom rather than competing
 * with them.
 *
 * The version and the link are asked for rather than written here. A number
 * typed into a page is out of date the day after it ships, and the API already
 * knows: `POST /init` with no install id answers with the update plan and
 * nothing else, and writes nothing down.
 */

const { public: config } = useRuntimeConfig()

const { data: android, pending, error } = await useAsyncData('release:android', () =>
  api.init('android'),
)

/** `null` when no download is configured yet — which is a thing to say, not to hide. */
const apk = computed(() => android.value?.update.url ?? null)

/**
 * The version, when there is one.
 *
 * `0.0.0` is the API's own default for a platform nothing has been published
 * for yet — a floor, not a release. Printing it would put a version number on a
 * page next to a download that does not exist.
 */
const version = computed(() => {
  const latest = android.value?.update.latest
  return latest && latest !== '0.0.0' ? latest : null
})

const steps = [
  'Увімкніть «Невідомі джерела» для файлового менеджера в налаштуваннях приставки.',
  'Завантажте APK — з цієї сторінки на телефоні або через Downloader на самій приставці.',
  'Відкрийте файл і встановіть. Після цього призначте лаунчер кнопкою HOME.',
]

useHead({ title: 'Завантажити — Сеанс' })
</script>

<template>
  <div class="downloads">
    <header>
      <h1>Завантажити</h1>
      <p class="lede">
        Той самий каталог, але як застосунок: на приставці він замінює головний екран, у
        браузері — встановлюється як окрема програма.
      </p>
    </header>

    <div class="cards">
      <section class="card">
        <div class="mono kick">ANDROID TV · APK</div>
        <h2>Лаунчер для приставки</h2>
        <p>
          Замінює головний екран Android TV: каталог, прямий ефір, ваші застосунки й диски —
          усе з пульта, без мишки. Працює на боксах і телевізорах з Android TV та Google TV.
        </p>

        <div v-if="version || pending || error" class="mono ver">
          <span v-if="version">Актуальна версія {{ version }}</span>
          <span v-else-if="error">Не вдалося спитати сервер про версію</span>
          <span v-else>Питаємо сервер про версію…</span>
        </div>

        <a v-if="apk" class="btn btn-primary" :href="apk" download>Завантажити APK</a>
        <div v-else class="mono note">
          Складання ще не опубліковане. Коли з’явиться, посилання буде тут — сторінка бере
          його з API, а не з тексту.
        </div>

        <ol class="steps">
          <li v-for="(step, index) in steps" :key="index">
            <span class="mono num">{{ String(index + 1).padStart(2, '0') }}</span>
            <span>{{ step }}</span>
          </li>
        </ol>
      </section>

      <section class="card">
        <div class="mono kick">БРАУЗЕР · PWA</div>
        <h2>Та сама програма у вкладці</h2>
        <p>
          Той самий Flutter-застосунок, зібраний під веб. Відкривається за посиланням, а через
          «Встановити застосунок» у браузері лягає окремим вікном з власною іконкою — без
          адресного рядка й без магазину.
        </p>

        <div class="mono ver">Оновлюється сам: перезавантаження — це і є нова версія</div>

        <a class="btn btn-primary" :href="config.tvUrl" target="_blank" rel="noreferrer">
          Відкрити застосунок
        </a>

        <ol class="steps">
          <li>
            <span class="mono num">01</span>
            <span>Chrome або Edge: значок встановлення праворуч в адресному рядку.</span>
          </li>
          <li>
            <span class="mono num">02</span>
            <span>Safari на iOS: «Поділитись» → «На екран “Домівка”».</span>
          </li>
          <li>
            <span class="mono num">03</span>
            <span>Керується і мишкою, і клавіатурою — стрілки та Enter, як пультом.</span>
          </li>
        </ol>
      </section>
    </div>

    <p class="tail">
      А цей сайт встановлювати не треба — каталог, пошук і список працюють просто у вкладці.
    </p>
  </div>
</template>

<style scoped>
.downloads {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
}

.lede {
  max-width: 62ch;
  margin: 14px 0 clamp(28px, 4vw, 44px);
  font-size: clamp(15px, 1.2vw, 18px);
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr));
  gap: clamp(16px, 2vw, 28px);
}

.card {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 14px;
  padding: clamp(22px, 3vw, 36px);
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
}

.kick {
  font-size: 11px;
  letter-spacing: 0.18em;
  color: var(--accent-300);
}

.card h2 {
  font-weight: 500;
  font-size: clamp(22px, 2.2vw, 30px);
  line-height: 1.15;
}

.card p {
  margin: 0;
  max-width: 52ch;
  font-size: 15px;
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

.ver {
  font-size: 12px;
  letter-spacing: 0.08em;
  color: var(--neutral-600);
}

.note {
  font-size: 12px;
  line-height: 1.7;
  color: var(--accent-300);
  max-width: 46ch;
}

.steps {
  list-style: none;
  margin: 8px 0 0;
  padding: 16px 0 0;
  border-top: 1px solid var(--hairline);
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.steps li {
  display: flex;
  gap: 14px;
  font-size: 14px;
  line-height: 1.55;
  color: var(--neutral-500);
}

.num {
  flex: none;
  font-size: 11px;
  letter-spacing: 0.12em;
  color: var(--neutral-700);
  padding-top: 3px;
}

.tail {
  margin: clamp(28px, 4vw, 44px) 0 0;
  font-size: 14px;
  color: var(--neutral-600);
}
</style>
