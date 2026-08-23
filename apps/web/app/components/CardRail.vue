<script setup lang="ts">
/**
 * A row that runs off the right edge.
 *
 * The arrows are the affordance, because the scrollbar is hidden: on a trackpad
 * the row scrolls under the finger and they are never touched, and on
 * everything else they are the only way to know the row continues.
 */

defineProps<{
  title: string
  /** Where the whole row leads, when it leads anywhere. */
  to?: string
}>()

const rail = ref<HTMLElement | null>(null)

function nudge(direction: 1 | -1): void {
  const element = rail.value
  if (!element) return
  // Most of a screenful, not all of it: the card that was at the edge stays on
  // screen, so there is something to carry the eye across the jump.
  element.scrollBy({ left: direction * Math.max(240, element.clientWidth * 0.8), behavior: 'smooth' })
}
</script>

<template>
  <section class="rail">
    <header>
      <NuxtLink v-if="to" :to="to" class="label heading">{{ title }}</NuxtLink>
      <h2 v-else class="label heading">{{ title }}</h2>
      <div class="arrows">
        <button type="button" class="btn btn-ghost arrow" aria-label="Ліворуч" @click="nudge(-1)">
          ←
        </button>
        <button type="button" class="btn btn-ghost arrow" aria-label="Праворуч" @click="nudge(1)">
          →
        </button>
      </div>
    </header>
    <div ref="rail" data-rail class="track">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.rail {
  padding-top: clamp(20px, 3vw, 36px);
}

header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px;
  padding: 0 var(--gutter);
  margin-bottom: 14px;
}

.heading {
  transition: color 160ms ease;
}

a.heading:hover {
  color: var(--accent-300);
}

.arrows {
  display: flex;
  gap: 6px;
}

.arrow {
  padding: 4px 12px;
  font-family: var(--font-mono);
  font-size: 15px;
  color: var(--neutral-500);
}

.track {
  display: flex;
  gap: clamp(12px, 1.4vw, 20px);
  overflow-x: auto;
  scroll-snap-type: x proximity;
  padding: 4px var(--gutter) 8px;
  /* Snapping happens *inside* the gutter, not against the window's edge —
     without this the first card lands under the page margin rather than at it. */
  scroll-padding-inline: var(--gutter);
  /* Room for the hover lift, so a raised card is not clipped by the row. */
  margin-top: -4px;
}

/* The cards say they are snap targets themselves — see `TitleCard`. Saying it
   from here would need `:deep`, and `:deep(*)` reaches every element inside a
   card rather than the card: the browser then snapped to the artwork *within*
   the first one and pulled the gutter off the left of every row. */
</style>
