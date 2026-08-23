<script setup lang="ts">
/**
 * One section of the catalogue, narrowed.
 *
 * The filters are the API's own: `genres` and `year` take slugs from
 * `/catalogue/filters`, never display names, and the section decides which of
 * them exist at all. They live in the address rather than in a ref — a filtered
 * page is a thing somebody sends to somebody else, and the browser's Back has
 * to walk back through them.
 */

import { CONTENT_TYPES, type Card, type ContentType } from '~/types/api'

const route = useRoute()
const router = useRouter()

const type = computed<ContentType | null>(() => {
  const value = route.params.type as string
  return (CONTENT_TYPES as readonly string[]).includes(value) ? (value as ContentType) : null
})

const genres = computed(() => {
  const raw = route.query.genres
  return typeof raw === 'string' && raw ? raw.split(',') : []
})

const year = computed(() => (typeof route.query.year === 'string' ? route.query.year : undefined))

/** Cached: it changes when a genre is added, which is not often. */
const { data: filters } = await useAsyncData('filters', () => api.filters())

const section = computed(() => (type.value ? filters.value?.by_type[type.value] : undefined))

/**
 * The popular ones, and the rest behind a word.
 *
 * The API splits them for a reason: a section carries thirty-odd genres, and a
 * wall of them is the first thing on the page and the last thing anybody reads.
 * Anything already chosen is always shown, so a filter can never be on and
 * invisible.
 */
const moreGenres = ref(false)

const allGenres = computed(() => {
  const popular = section.value?.popular_genres ?? []
  const rest = section.value?.other_genres ?? []
  if (moreGenres.value) return [...popular, ...rest]
  return [...popular, ...rest.filter((one) => genres.value.includes(one.slug))]
})

const hiddenGenres = computed(() =>
  moreGenres.value
    ? 0
    : (section.value?.other_genres ?? []).filter((one) => !genres.value.includes(one.slug)).length,
)

/**
 * The pages fetched so far, appended rather than replaced.
 *
 * Ambient's grid is one long page with a button at the end, not a pager: the
 * catalogue is ordered by what changed most recently, so page two is the rest
 * of the same thought rather than a separate place.
 */
const items = ref<Card[]>([])
const page = ref(1)
const total = ref(0)
const more = ref(false)
const busy = ref(false)
const failed = ref<string | null>(null)

async function fetchPage(next: number): Promise<void> {
  if (!type.value) return
  busy.value = true
  failed.value = null
  try {
    const answer = await api.catalog({
      type: type.value,
      page: next,
      genres: genres.value.length ? genres.value : undefined,
      year: year.value,
    })
    items.value = next === 1 ? answer.items : [...items.value, ...answer.items]
    page.value = answer.meta.page
    total.value = answer.meta.total
    more.value = answer.meta.has_next_page
  } catch (error) {
    failed.value = error instanceof ApiError ? error.message : 'Не вдалося завантажити розділ'
  } finally {
    busy.value = false
  }
}

// The section and the filters are all in the address, so one watcher covers
// every way the page can change — including the browser's own Back.
watch(
  () => [type.value, genres.value.join(','), year.value] as const,
  () => fetchPage(1),
  { immediate: true },
)

/** Toggling a filter always starts the list again: page 4 of a different question is nothing. */
function toggleGenre(slug: string): void {
  const next = genres.value.includes(slug)
    ? genres.value.filter((one) => one !== slug)
    : [...genres.value, slug]
  router.push({ query: { ...route.query, genres: next.length ? next.join(',') : undefined } })
}

function chooseYear(slug: string | undefined): void {
  router.push({ query: { ...route.query, year: year.value === slug ? undefined : slug } })
}

useHead(() => ({ title: `${sectionName(type.value)} — Сеанс` }))
</script>

<template>
  <div class="section">
    <header>
      <h1>{{ sectionName(type) }}</h1>
      <div v-if="total" class="mono count">{{ total }} тайтлів</div>
    </header>

    <div v-if="allGenres.length" class="filters">
      <div class="label">Жанр</div>
      <div class="chips">
        <button
          v-for="genre in allGenres"
          :key="genre.slug"
          type="button"
          class="chip"
          :class="{ on: genres.includes(genre.slug) }"
          @click="toggleGenre(genre.slug)"
        >
          {{ genre.name }}
        </button>
        <button
          v-if="hiddenGenres"
          type="button"
          class="chip more"
          @click="moreGenres = true"
        >
          Ще {{ hiddenGenres }}
        </button>
      </div>
    </div>

    <div v-if="section?.years.length" class="filters">
      <div class="label">Рік</div>
      <div class="chips">
        <button
          v-for="one in section.years"
          :key="one.slug"
          type="button"
          class="chip"
          :class="{ on: year === one.slug }"
          @click="chooseYear(one.slug)"
        >
          {{ one.name }}
        </button>
      </div>
    </div>

    <div v-if="items.length" class="grid">
      <TitleCard v-for="card in items" :key="card.slug" :card="card" />
    </div>

    <StatusNote
      :loading="busy && !items.length"
      :error="failed"
      :empty="!busy && !items.length ? 'За цими фільтрами нічого немає' : null"
    />

    <div v-if="more" class="more">
      <button type="button" class="btn" :disabled="busy" @click="fetchPage(page + 1)">
        {{ busy ? 'Завантажуємо…' : 'Показати ще' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.section {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
}

header {
  display: flex;
  align-items: baseline;
  gap: 20px;
  flex-wrap: wrap;
  margin-bottom: clamp(20px, 3vw, 36px);
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
}

.count {
  font-size: 13px;
  letter-spacing: 0.12em;
  color: var(--neutral-600);
}

.filters {
  display: flex;
  align-items: baseline;
  gap: 18px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}

.filters .label {
  flex: none;
  width: 72px;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

/* A chip is a tag that answers: an outline that fills with the accent's tint
   when it is on, never a solid accent. */
.chip {
  cursor: pointer;
  padding: 7px 14px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: transparent;
  font-family: var(--font-body);
  font-size: 14px;
  color: var(--neutral-400);
  transition:
    border-color 160ms ease,
    background 160ms ease,
    color 160ms ease;
}

.chip:hover {
  border-color: var(--neutral-600);
  color: var(--text);
}

.chip.on {
  border-color: var(--accent);
  background: var(--accent-veil);
  color: var(--text);
}

.chip.more {
  border-style: dashed;
  font-family: var(--font-mono);
  font-size: 12px;
  letter-spacing: 0.08em;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 200px), 1fr));
  gap: clamp(12px, 1.6vw, 24px);
  margin-top: clamp(20px, 3vw, 32px);
}

.more {
  display: flex;
  justify-content: center;
  padding: clamp(28px, 4vw, 48px) 0 0;
}
</style>
