<script setup lang="ts">
/**
 * One title in a rail or a grid.
 *
 * Two shapes, one component: a 2:3 poster is the catalogue's own artwork, and a
 * 16:9 still is what trending and the slider carry. Which one a card *has*
 * decides nothing — the row it sits in does, so the shape is a prop.
 */

import type { Card } from '~/types/api'

const props = withDefaults(
  defineProps<{
    card: Card
    /** 16:9 rather than 2:3, for a rail drawn from wide artwork. */
    wide?: boolean
    /** 0–1, drawn as a line along the bottom edge. Zero draws nothing. */
    resume?: number
  }>(),
  { wide: false, resume: 0 },
)

/**
 * Wide artwork where it exists and the poster where it does not: a title that
 * has never been on the slider still belongs in "Продовжити дивитись".
 */
const art = computed(() =>
  props.wide
    ? (props.card.slider_poster_url ?? props.card.slider_url ?? props.card.poster_url)
    : props.card.poster_url,
)

// A broken image is left off rather than left showing the browser's own torn
// icon; the gradient underneath was drawn for exactly this.
const broken = ref(false)
watch(art, () => (broken.value = false))
</script>

<template>
  <NuxtLink class="card" :to="`/title/${card.slug}`">
    <div
      class="art"
      :class="wide ? 'art-wide' : 'art-poster'"
      :style="{ background: artBackground(card.slug) }"
    >
      <img
        v-if="art && !broken"
        :src="art"
        :alt="card.name"
        loading="lazy"
        decoding="async"
        @error="broken = true"
      />
      <div class="shade" />
      <div class="name">{{ card.name }}</div>
      <div v-if="resume > 0" class="resume" :style="{ width: `${Math.round(resume * 100)}%` }" />
    </div>
    <div class="meta mono">{{ cardMeta(card) }}</div>
  </NuxtLink>
</template>

<style scoped>
.card {
  display: flex;
  flex-direction: column;
  gap: 9px;
  transition: transform 220ms cubic-bezier(0.33, 0, 0.15, 1);
  /* For the rail it may be sitting in. Both are inert in a grid, and a card is
     the only thing that should ever be a snap target — a rail cannot say so
     from outside without reaching into the card's own elements. */
  flex: 0 0 auto;
  scroll-snap-align: start;
}

.card:hover {
  transform: translateY(-6px);
}

.art-poster {
  aspect-ratio: 2 / 3;
}

.art-wide {
  aspect-ratio: 16 / 9;
}

.art img {
  position: absolute;
  inset: 0;
}

.name {
  position: absolute;
  left: 12px;
  right: 12px;
  bottom: 12px;
  font-family: var(--font-display);
  font-weight: 700;
  font-size: clamp(14px, 1.3vw, 20px);
  line-height: 1.15;
  text-shadow: 0 2px 12px rgba(0, 0, 0, 0.6);
}

/* The one place a solid accent is allowed to run: it is a measurement, four
   pixels tall, and reading it is the whole point. */
.resume {
  position: absolute;
  left: 0;
  bottom: 0;
  height: 4px;
  background: var(--accent);
}

.meta {
  font-size: clamp(11px, 0.95vw, 14px);
  color: var(--neutral-600);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
