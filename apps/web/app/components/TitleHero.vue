<script setup lang="ts">
/**
 * The first screen: one title, at the size of a poster in a foyer.
 *
 * Everything under the artwork is a gradient rather than a panel — the picture
 * runs edge to edge and the text sits on it, which only works because the two
 * gradients (one across, one up) are doing the job a scrim would do.
 */

import type { Card } from '~/types/api'

const props = defineProps<{
  card: Card
  /** Whether this browser has this one half-watched. Changes the first button. */
  resumeAt?: number | null
}>()

const emit = defineEmits<{ play: [] }>()

const open = ref(false)
watch(
  () => props.card.slug,
  () => (open.value = false),
)

const art = computed(() => props.card.slider_url ?? props.card.slider_poster_url ?? props.card.poster_url)

const facts = computed(() => [
  { label: 'ТРИВАЛІСТЬ', value: props.card.time ?? '—' },
  { label: 'ЖАНР', value: props.card.genres.map((one) => one.name).join(', ') || '—' },
  { label: 'РІК', value: props.card.year_label ?? '—' },
  {
    label: 'РЕЙТИНГ',
    value: props.card.imdb_mark ? `★ ${props.card.imdb_mark.toFixed(1)}` : '—',
  },
])
</script>

<template>
  <section class="hero">
    <div class="backdrop" :style="{ background: artBackground(card.slug) }">
      <img v-if="art" :src="art" :alt="''" fetchpriority="high" />
    </div>
    <div class="scrim" />
    <div class="body">
      <div class="mono kicker">{{ heroMeta(card) }}</div>
      <h1>{{ card.name }}</h1>
      <p v-if="card.short_description" class="lede">{{ card.short_description }}</p>
      <div v-if="card.original_name && card.original_name !== card.name" class="mono original">
        {{ card.original_name }}
      </div>
      <div class="actions">
        <button type="button" class="btn btn-primary" @click="emit('play')">
          {{ resumeAt ? 'Продовжити' : 'Дивитись' }}
        </button>
        <NuxtLink class="btn" :to="`/title/${card.slug}`">Про фільм</NuxtLink>
        <button type="button" class="btn" @click="open = !open">
          {{ open ? 'Згорнути' : 'Деталі' }}
        </button>
      </div>
      <div v-if="open" class="facts">
        <div v-for="fact in facts" :key="fact.label">
          <div class="label-sm">{{ fact.label }}</div>
          {{ fact.value }}
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.hero {
  position: relative;
  display: flex;
  align-items: flex-end;
  min-height: clamp(460px, 74vh, 720px);
  padding: clamp(40px, 8vh, 96px) var(--gutter) clamp(32px, 6vh, 64px);
  overflow: hidden;
  /* Pulled up under the bar, which is translucent and expects to sit on this. */
  margin-top: -66px;
  padding-top: calc(66px + clamp(40px, 8vh, 96px));
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

/* Across, then up: the words sit on the left, and the rails below have to come
   out of the picture rather than start against an edge. */
.scrim {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(
      90deg,
      color-mix(in srgb, var(--ground) 94%, transparent) 0%,
      color-mix(in srgb, var(--ground) 64%, transparent) 45%,
      transparent 88%
    ),
    linear-gradient(0deg, var(--ground) 0%, transparent 46%);
}

.body {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: clamp(12px, 1.6vw, 20px);
  max-width: min(640px, 92%);
}

.kicker {
  font-size: clamp(12px, 1.1vw, 15px);
  letter-spacing: 0.14em;
  color: var(--accent-300);
}

h1 {
  font-weight: 700;
  font-size: clamp(38px, 6.4vw, 84px);
  line-height: 1.03;
  letter-spacing: -0.01em;
  text-wrap: balance;
}

.lede {
  margin: 0;
  font-size: clamp(15px, 1.4vw, 20px);
  line-height: 1.55;
  color: var(--neutral-300);
  text-wrap: pretty;
}

.original {
  font-size: clamp(11px, 1vw, 14px);
  color: var(--neutral-600);
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 8px;
}

.facts {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 14px 28px;
  margin-top: 6px;
  padding-top: 18px;
  border-top: 1px solid var(--divider);
  font-size: 14px;
  color: var(--neutral-400);
}

.facts .label-sm {
  margin-bottom: 4px;
}
</style>
