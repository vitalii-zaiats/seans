<script setup lang="ts">
/**
 * The home screen: one title at the size of a foyer poster, and rows under it.
 *
 * The order of the rows is the television's, and for its reason — what somebody
 * stopped halfway through is the likeliest thing they came back for, so it goes
 * first; the catalogue's own sections follow in the order the API lists them.
 * The two rows in between are this browser's own, and nothing else can build
 * them: they are read out of `localStorage` and looked up by slug.
 */

import { CONTENT_TYPES, type Card } from '~/types/api'

const library = useLibrary()
const player = usePlayer()

const { data, pending, error } = await useAsyncData('home', async () => {
  const [hero, trending, ...sections] = await Promise.all([
    api.slider(),
    api.trending(),
    ...CONTENT_TYPES.map((type) => api.catalog({ type })),
  ])
  return {
    hero: hero.items,
    trending: trending.items,
    sections: CONTENT_TYPES.map((type, index) => ({
      type,
      title: sectionName(type),
      items: sections[index]?.items ?? [],
    })),
  }
})

/**
 * The two local rows, resolved to cards.
 *
 * Refetched whenever the lists change — saving a title from its own page is
 * supposed to be visible when you come back here, and the alternative is a row
 * that is right only until somebody touches it.
 */
const slugs = computed(() => ({
  resume: library.resumable.value.map((one) => one.slug),
  saved: library.list.value,
}))

const { data: mine } = await useAsyncData(
  'home-mine',
  async () => {
    const wanted = [...new Set([...slugs.value.resume, ...slugs.value.saved])]
    if (wanted.length === 0) return { byslug: new Map<string, Card>() }
    const cards = await api.cards(wanted)
    return { byslug: new Map(cards.items.map((card) => [card.slug, card])) }
  },
  { watch: [slugs] },
)

/** In the order they were watched, and only the ones the catalogue still knows. */
const resume = computed(() =>
  library.resumable.value.flatMap((entry) => {
    const card = mine.value?.byslug.get(entry.slug)
    return card ? [{ card, entry }] : []
  }),
)

const saved = computed(() =>
  library.list.value.flatMap((slug) => {
    const card = mine.value?.byslug.get(slug)
    return card ? [card] : []
  }),
)

/** A section with nothing in it is a row of nothing — left out rather than drawn empty. */
const sections = computed(() => (data.value?.sections ?? []).filter((one) => one.items.length))

/* ── the hero, which moves on ─────────────────────────────────────────────── */

const heroIndex = ref(0)
const held = ref(false)
const hero = computed<Card | null>(() => data.value?.hero[heroIndex.value] ?? null)

let turning: ReturnType<typeof setInterval> | undefined

onMounted(() => {
  // Nine seconds is long enough to read the synopsis and short enough that a
  // second title is visibly on offer. Held while the pointer is on it: moving
  // the poster out from under somebody reading it is the rudest thing a home
  // screen can do.
  turning = setInterval(() => {
    const count = data.value?.hero.length ?? 0
    if (!held.value && count > 1) heroIndex.value = (heroIndex.value + 1) % count
  }, 9000)
})

onBeforeUnmount(() => clearInterval(turning))
</script>

<template>
  <div>
    <StatusNote :loading="pending" :error="error ? 'Не вдалося завантажити каталог' : null" />

    <div v-if="hero" @mouseenter="held = true" @mouseleave="held = false">
      <TitleHero
        :card="hero"
        :resume-at="library.progressFor(hero.slug)?.position ?? null"
        @play="player.play(hero)"
      />
      <div v-if="(data?.hero.length ?? 0) > 1" class="marks">
        <button
          v-for="(one, index) in data?.hero"
          :key="one.slug"
          type="button"
          class="mark"
          :class="{ on: index === heroIndex }"
          :aria-label="one.name"
          @click="heroIndex = index"
        />
      </div>
    </div>

    <CardRail v-if="resume.length" title="Продовжити дивитись">
      <TitleCard
        v-for="one in resume"
        :key="one.card.slug"
        :card="one.card"
        wide
        :resume="fractionOf(one.entry)"
        class="wide"
      />
    </CardRail>

    <!--
      Posters, not stills. Trending carries wide artwork and used to draw it,
      which put two rows of the same shape next to each other and made the rail
      read as more "Продовжити дивитись" rather than as a different thing. The
      row above keeps the wide shape precisely because it is the one that is
      about a thing already started.
    -->
    <CardRail v-if="data?.trending.length" title="У тренді">
      <TitleCard v-for="card in data.trending" :key="card.slug" :card="card" class="poster" />
    </CardRail>

    <CardRail v-if="saved.length" title="Мій список" to="/list">
      <TitleCard v-for="card in saved" :key="card.slug" :card="card" class="poster" />
    </CardRail>

    <CardRail
      v-for="section in sections"
      :key="section.type"
      :title="section.title"
      :to="`/catalog/${section.type}`"
    >
      <TitleCard v-for="card in section.items" :key="card.slug" :card="card" class="poster" />
    </CardRail>

    <PlayerOverlay
      v-if="player.playing.value"
      :slug="player.playing.value.slug"
      :title="player.playing.value.title"
      :meta="player.playing.value.meta"
      :art="player.playing.value.art"
      :src="player.playing.value.src"
      :start-at="player.playing.value.startAt"
      :failed="player.playing.value.failed"
      :live="player.playing.value.live"
      @close="player.close"
      @progress="player.remember($event.position, $event.duration)"
    />
  </div>
</template>

<style scoped>
/* The hero's own index, drawn the way the design system draws a step: short
   accent marks, solid, and the one you are on is longer rather than brighter. */
.marks {
  display: flex;
  gap: 8px;
  padding: 0 var(--gutter);
}

/* Three pixels tall, so they need a step the ground does not swallow: 800 is a
   border colour and disappears against the hero's own gradient. */
.mark {
  width: 18px;
  height: 3px;
  padding: 0;
  border: 0;
  cursor: pointer;
  background: var(--neutral-700);
  transition:
    width 220ms ease,
    background 220ms ease;
}

.mark:hover {
  background: var(--neutral-500);
}

.mark.on {
  width: 34px;
  background: var(--accent);
}

/* A rail's cards are sized here rather than inside the card: the same card is
   a poster in one row and a still in another, and how wide it is belongs to
   the row it is in. */
.wide {
  width: clamp(240px, 26vw, 380px);
}

.poster {
  width: clamp(140px, 15vw, 210px);
}
</style>
