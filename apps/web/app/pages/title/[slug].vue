<script setup lang="ts">
/**
 * One title, in full.
 *
 * A series arrives with every season it ever had and the episodes of exactly
 * one — the rest come back empty, which reads like "nothing to watch" and is
 * not the same thing. `is_loaded` is what tells them apart, and picking another
 * season asks for it by name rather than hoping.
 */

const route = useRoute()
const library = useLibrary()
const player = usePlayer()

const slug = computed(() => route.params.slug as string)
const season = ref<number | null>(null)

const { data: details, pending, error } = await useAsyncData(
  () => `title:${slug.value}:${season.value ?? 'first'}`,
  () => api.content(slug.value, season.value ?? undefined),
  { watch: [slug, season] },
)

/** The season being shown: the one asked for, or whatever came filled in. */
const current = computed(() => {
  const seasons = details.value?.seasons ?? []
  return seasons.find((one) => one.number === season.value) ?? seasons.find((one) => one.is_loaded) ?? seasons[0] ?? null
})

const saved = computed(() => library.isSaved(slug.value))
const progress = computed(() => library.progressFor(slug.value))

const backdrop = computed(() => details.value?.slider_url ?? details.value?.poster_url ?? null)

const facts = computed(() => {
  const one = details.value
  if (!one) return []
  return [
    { label: 'ТРИВАЛІСТЬ', value: one.time },
    { label: 'КРАЇНА', value: one.country },
    { label: 'РІК', value: yearLabel(one) },
    { label: 'IMDB', value: one.imdb_mark ? one.imdb_mark.toFixed(1) : null },
    { label: 'ВІК', value: one.age_restrictions ? `${one.age_restrictions}+` : null },
    { label: 'СЕЗОНИ', value: one.is_series ? String(one.seasons.length) : null },
  ].filter((fact) => fact.value)
})

function playEpisode(number?: number): void {
  const one = details.value
  if (!one) return
  player.play(one, { season: current.value?.number ?? null, episode: number ?? null, from: number ? 0 : undefined })
}

useHead(() => ({ title: details.value ? `${details.value.name} — Сеанс` : 'Сеанс' }))
</script>

<template>
  <div>
    <StatusNote
      :loading="pending && !details"
      :error="error ? 'Не вдалося відкрити тайтл' : null"
    />

    <article v-if="details">
      <section class="top">
        <div class="backdrop" :style="{ background: artBackground(details.slug) }">
          <img v-if="backdrop" :src="backdrop" alt="" />
        </div>
        <div class="scrim" />

        <div class="body">
          <div class="poster art">
            <img :src="details.poster_url" :alt="details.name" />
          </div>

          <div class="words">
            <div class="mono kicker">{{ heroMeta(details) }}</div>
            <h1>{{ details.name }}</h1>
            <div v-if="details.original_name !== details.name" class="mono original">
              {{ details.original_name }}
            </div>

            <p v-if="details.short_description" class="lede">{{ details.short_description }}</p>

            <div class="actions">
              <button
                type="button"
                class="btn btn-primary"
                :disabled="!details.is_playable"
                @click="playEpisode()"
              >
                {{ progress ? 'Продовжити' : 'Дивитись' }}
              </button>
              <button type="button" class="btn" @click="library.toggleSaved(details.slug)">
                {{ saved ? 'У списку ✓' : 'До списку' }}
              </button>
            </div>

            <div v-if="!details.is_playable" class="mono warn">
              Цей тайтл поки що ні на чому дивитись — каталог його показує, але жоден плеєр
              не віддає доріжку.
            </div>

            <dl class="facts">
              <div v-for="fact in facts" :key="fact.label">
                <dt class="label-sm">{{ fact.label }}</dt>
                <dd>{{ fact.value }}</dd>
              </div>
            </dl>

            <div v-if="details.genres.length" class="genres">
              <NuxtLink
                v-for="genre in details.genres"
                :key="genre.slug"
                class="chip"
                :to="`/catalog/${details.type ?? 'movie'}?genres=${genre.slug}`"
              >
                {{ genre.name }}
              </NuxtLink>
            </div>
          </div>
        </div>
      </section>

      <section v-if="details.is_series && details.seasons.length" class="block">
        <h2 class="label">Сезони</h2>
        <div class="chips">
          <button
            v-for="one in details.seasons"
            :key="one.id"
            type="button"
            class="chip"
            :class="{ on: current?.number === one.number }"
            @click="season = one.number"
          >
            Сезон {{ one.number }}
          </button>
        </div>

        <div v-if="current && current.episodes.length" class="episodes">
          <button
            v-for="episode in current.episodes"
            :key="episode.number"
            type="button"
            class="episode"
            :disabled="!episode.ready"
            @click="playEpisode(episode.number)"
          >
            <span class="mono number">{{ String(episode.number).padStart(2, '0') }}</span>
            <span class="title">{{ episode.name ?? `Серія ${episode.number}` }}</span>
            <span v-if="!episode.ready" class="mono soon">ще не вийшла</span>
          </button>
        </div>
        <div v-else-if="current && !current.is_loaded" class="mono empty">
          Цей сезон каталог ще не заповнив.
        </div>
      </section>

      <section v-if="details.cast.length" class="block">
        <h2 class="label">У ролях</h2>
        <div class="people">
          <div v-for="one in details.cast.slice(0, 18)" :key="one.slug + one.character" class="person">
            <div class="face art" :style="{ background: artBackground(one.slug) }">
              <img v-if="one.poster_url" :src="one.poster_url" :alt="one.name" loading="lazy" />
            </div>
            <div class="who">{{ one.name }}</div>
            <div v-if="one.character" class="mono role">{{ one.character }}</div>
          </div>
        </div>
      </section>

      <section v-if="details.franchise?.items.length" class="block">
        <h2 class="label">{{ details.franchise.name }}</h2>
        <div class="grid">
          <NuxtLink
            v-for="one in details.franchise.items"
            :key="one.slug"
            class="franchise"
            :to="`/title/${one.slug}`"
          >
            <div class="art poster-small" :style="{ background: artBackground(one.slug) }">
              <img v-if="one.poster_url" :src="one.poster_url" :alt="one.name" loading="lazy" />
              <div class="shade" />
              <div class="fname">{{ one.name }}</div>
            </div>
          </NuxtLink>
        </div>
      </section>
    </article>

    <PlayerOverlay
      v-if="player.playing.value"
      :slug="player.playing.value.slug"
      :title="player.playing.value.title"
      :meta="player.playing.value.meta"
      :art="player.playing.value.art"
      :src="player.playing.value.src"
      :start-at="player.playing.value.startAt"
      :failed="player.playing.value.failed"
      @close="player.close"
      @progress="player.remember($event.position, $event.duration)"
    />
  </div>
</template>

<style scoped>
.top {
  position: relative;
  padding: clamp(40px, 7vh, 96px) var(--gutter) clamp(28px, 4vw, 56px);
  margin-top: -66px;
  padding-top: calc(66px + clamp(40px, 7vh, 96px));
  overflow: hidden;
}

.backdrop {
  position: absolute;
  inset: -40px;
  background-size: cover;
}

.backdrop img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.scrim {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(
      90deg,
      color-mix(in srgb, var(--ground) 95%, transparent) 0%,
      color-mix(in srgb, var(--ground) 72%, transparent) 55%,
      color-mix(in srgb, var(--ground) 40%, transparent) 100%
    ),
    linear-gradient(0deg, var(--ground) 0%, transparent 52%);
}

.body {
  position: relative;
  display: flex;
  gap: clamp(20px, 3vw, 44px);
  align-items: flex-start;
}

.poster {
  flex: none;
  width: clamp(150px, 18vw, 260px);
  aspect-ratio: 2 / 3;
}

.words {
  display: flex;
  flex-direction: column;
  gap: 14px;
  min-width: 0;
  max-width: 760px;
}

.kicker {
  font-size: clamp(11px, 1vw, 14px);
  letter-spacing: 0.14em;
  color: var(--accent-300);
}

h1 {
  font-weight: 700;
  font-size: clamp(30px, 4.6vw, 64px);
  line-height: 1.04;
  letter-spacing: -0.01em;
  text-wrap: balance;
}

.original {
  font-size: 13px;
  color: var(--neutral-600);
  margin-top: -8px;
}

.lede {
  margin: 0;
  font-size: clamp(15px, 1.2vw, 18px);
  line-height: 1.6;
  color: var(--neutral-300);
  text-wrap: pretty;
}

.actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  margin-top: 4px;
}

.warn {
  font-size: 13px;
  line-height: 1.6;
  color: var(--accent-300);
  max-width: 60ch;
}

.facts {
  display: flex;
  flex-wrap: wrap;
  gap: 12px 32px;
  margin: 8px 0 0;
}

.facts dt {
  margin-bottom: 4px;
}

.facts dd {
  margin: 0;
  font-size: 15px;
}

.genres,
.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.chip {
  display: inline-block;
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

.block {
  padding: clamp(28px, 4vw, 48px) var(--gutter) 0;
}

.block .label {
  margin-bottom: 16px;
}

.episodes {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 320px), 1fr));
  gap: 8px;
  margin-top: 18px;
}

.episode {
  display: flex;
  align-items: center;
  gap: 14px;
  cursor: pointer;
  text-align: left;
  padding: 14px 16px;
  border-radius: var(--radius);
  border: 1px solid transparent;
  background: var(--surface);
  transition:
    border-color 160ms ease,
    background 160ms ease;
}

.episode:hover:not(:disabled) {
  border-color: var(--accent);
  background: var(--accent-veil);
}

.episode:disabled {
  opacity: 0.45;
  cursor: default;
}

.episode .number {
  color: var(--neutral-600);
  font-size: 13px;
}

.episode .title {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.soon {
  font-size: 11px;
  letter-spacing: 0.1em;
  color: var(--neutral-600);
}

.empty {
  font-size: 13px;
  color: var(--neutral-600);
  margin-top: 16px;
}

.people {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 16px;
}

.person {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.face {
  aspect-ratio: 1 / 1;
  border-radius: 50%;
}

.face img {
  position: absolute;
  inset: 0;
}

.who {
  font-size: 14px;
}

.role {
  font-size: 11px;
  color: var(--neutral-600);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 160px), 1fr));
  gap: 14px;
}

.poster-small {
  aspect-ratio: 2 / 3;
}

.poster-small img {
  position: absolute;
  inset: 0;
}

.fname {
  position: absolute;
  left: 10px;
  right: 10px;
  bottom: 10px;
  font-family: var(--font-display);
  font-weight: 500;
  font-size: 14px;
  line-height: 1.2;
  text-shadow: 0 2px 12px rgba(0, 0, 0, 0.6);
}

.franchise {
  transition: transform 220ms cubic-bezier(0.33, 0, 0.15, 1);
  display: block;
}

.franchise:hover {
  transform: translateY(-6px);
}

@media (max-width: 720px) {
  .body {
    flex-direction: column;
  }

  .poster {
    width: clamp(140px, 42vw, 220px);
  }
}
</style>
