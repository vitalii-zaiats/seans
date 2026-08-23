<script setup lang="ts">
/**
 * Live television, at `/live` and deliberately not at `/tv`.
 *
 * `/tv/` is the API's — `/tv/channels`, `/tv/channels/{id}/stream` — so a page
 * there is eaten by the front door before it reaches this bundle. That is the
 * rule `deploy/caddy/Caddyfile` states, and naming this file `tv.vue` walked
 * straight into it.
 *
 * A grid of channels rather than rails: there is no "continue watching" a
 * channel and no ordering worth inventing, so the only structure that means
 * anything is the categories the list arrives with.
 *
 * Playing one is a single request — a channel's lease already carries a
 * playable address, unlike a film, which has to have its player page read
 * first.
 */

import type { TvChannel } from '~/types/api'

const player = usePlayer()

const { data, pending, error } = await useAsyncData('tv', () => api.channels())

/** Which chip is on. Null is everything, which is also what `is_all` means. */
const category = ref<number | null>(null)

const categories = computed(() => (data.value?.categories ?? []).filter((one) => !one.is_all))

const channels = computed(() => {
  const all = data.value?.items ?? []
  if (category.value === null) return all
  return all.filter((one) => one.categories.includes(category.value!))
})

/**
 * A channel's own colour behind a missing icon.
 *
 * Most carry one; the rest get the accent at a tint, which is still better
 * than an empty square in a grid of logos.
 */
function tile(channel: TvChannel): string {
  return channel.colour
    ? `linear-gradient(160deg, ${channel.colour} 0%, color-mix(in srgb, ${channel.colour} 40%, #000) 100%)`
    : artBackground(channel.slug)
}

useHead({ title: 'ТБ — Сеанс' })
</script>

<template>
  <div class="tv">
    <header>
      <h1>Телебачення</h1>
      <div v-if="channels.length" class="mono count">{{ channels.length }} каналів</div>
    </header>

    <div v-if="categories.length" class="chips">
      <button
        type="button"
        class="chip"
        :class="{ on: category === null }"
        @click="category = null"
      >
        Усі
      </button>
      <button
        v-for="one in categories"
        :key="one.id"
        type="button"
        class="chip"
        :class="{ on: category === one.id }"
        @click="category = one.id"
      >
        {{ one.title }}
      </button>
    </div>

    <div v-if="channels.length" class="grid">
      <button
        v-for="channel in channels"
        :key="channel.id"
        type="button"
        class="channel"
        @click="player.playChannel(channel)"
      >
        <span class="art logo" :style="{ background: tile(channel) }">
          <img v-if="channel.icon_url" :src="channel.icon_url" :alt="channel.name" loading="lazy" />
        </span>
        <span class="name">{{ channel.name }}</span>
        <span v-if="channel.now_playing" class="mono now">{{ channel.now_playing }}</span>
      </button>
    </div>

    <StatusNote
      :loading="pending"
      :error="error ? 'Не вдалося дістати список каналів' : null"
      :empty="!pending && !channels.length ? 'У цій категорії каналів немає' : null"
    />

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
.tv {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
}

header {
  display: flex;
  align-items: baseline;
  gap: 20px;
  flex-wrap: wrap;
  margin-bottom: clamp(18px, 2.4vw, 28px);
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

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: clamp(20px, 3vw, 32px);
}

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

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 170px), 1fr));
  gap: clamp(12px, 1.6vw, 22px);
}

.channel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 0;
  border: 0;
  background: transparent;
  text-align: left;
  cursor: pointer;
  transition: transform 220ms cubic-bezier(0.33, 0, 0.15, 1);
}

.channel:hover {
  transform: translateY(-6px);
}

/* 16:9 rather than a square: a channel logo is drawn wide, and a square crops
   half of most of them. */
.logo {
  aspect-ratio: 16 / 9;
  display: grid;
  place-items: center;
  padding: 14px;
}

.logo img {
  width: 100%;
  height: 100%;
  object-fit: contain;
}

.name {
  font-size: 15px;
  line-height: 1.2;
}

.now {
  font-size: 11px;
  color: var(--neutral-600);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
