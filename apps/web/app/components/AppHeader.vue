<script setup lang="ts">
/**
 * The bar over everything: where you are, where else you can be, and who you
 * are if anybody asked.
 *
 * Sticky and blurred, as the Ambient board has it — the hero runs under it
 * rather than starting below it, which is what keeps the first screen one
 * picture instead of two bands.
 */

import { CONTENT_TYPES } from '~/types/api'

const sections = CONTENT_TYPES.map((type) => ({
  type,
  title: sectionName(type),
  to: `/catalog/${type}`,
}))

const { account } = useAccount()

/**
 * The clock, to the minute.
 *
 * A television has one in the corner and this is the same idea: something on
 * the page that is true right now. Twenty seconds is often enough that the
 * minute is never visibly wrong, and rare enough to cost nothing.
 */
const now = ref(new Date())
let ticking: ReturnType<typeof setInterval> | undefined

onMounted(() => {
  ticking = setInterval(() => (now.value = new Date()), 20_000)
})

onBeforeUnmount(() => clearInterval(ticking))

const clock = computed(
  () => `${now.value.getHours()}:${String(now.value.getMinutes()).padStart(2, '0')}`,
)

/** One letter is enough at 34px, and a name nobody gave has none. */
const initial = computed(() => account.value?.display_name?.trim().slice(0, 1).toUpperCase() ?? '')
</script>

<template>
  <header class="chrome">
    <div class="left">
      <NuxtLink to="/" class="brand">SEANS</NuxtLink>
      <nav>
        <NuxtLink v-for="one in sections" :key="one.type" :to="one.to">{{ one.title }}</NuxtLink>
        <NuxtLink to="/live">ТБ</NuxtLink>
        <NuxtLink to="/list">Мій список</NuxtLink>
        <NuxtLink to="/downloads">Завантажити</NuxtLink>
      </nav>
    </div>
    <div class="right">
      <!-- The field where there is room for it, and the way to the page where
           there is not — see the media queries below. -->
      <SearchBox />
      <NuxtLink to="/search" class="btn btn-ghost find" aria-label="Пошук">Пошук</NuxtLink>
      <div class="mono clock">{{ clock }}</div>
      <NuxtLink to="/account" class="who" :aria-label="account ? account.display_name : 'Акаунт'">
        {{ initial }}
      </NuxtLink>
    </div>
  </header>
</template>

<style scoped>
.chrome {
  position: sticky;
  top: 0;
  z-index: 40;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 14px var(--gutter);
  /* Translucent rather than solid: the hero's own colour shows through, which
     is what makes the bar read as part of the picture. */
  background: color-mix(in srgb, var(--ground) 72%, transparent);
  backdrop-filter: blur(16px);
  border-bottom: 1px solid var(--hairline);
}

.left {
  display: flex;
  align-items: center;
  gap: clamp(16px, 3vw, 44px);
  min-width: 0;
}

.brand {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: clamp(15px, 1.4vw, 19px);
  letter-spacing: 0.22em;
  white-space: nowrap;
}

nav {
  display: flex;
  gap: clamp(12px, 2vw, 28px);
  font-size: 15px;
  overflow: hidden;
}

nav a {
  color: var(--neutral-500);
  white-space: nowrap;
  transition: color 160ms ease;
}

nav a:hover {
  color: var(--text);
}

/* `NuxtLink` sets this on the link whose route is showing. */
nav a.router-link-active {
  color: var(--text);
}

.right {
  display: flex;
  align-items: center;
  gap: 16px;
}

/* The link is the narrow-screen face of the same thing: below the breakpoint
   the bar has no room for a field, and the page has all the room there is. */
.find {
  display: none;
  padding: 6px 14px;
  font-size: 14px;
  color: var(--neutral-400);
}

.clock {
  font-size: 14px;
  letter-spacing: 0.06em;
  color: var(--neutral-600);
  white-space: nowrap;
}

.who {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  flex: none;
  border-radius: 50%;
  border: 1px solid var(--neutral-800);
  background: linear-gradient(135deg, var(--accent-800), var(--neutral-900));
  font-family: var(--font-display);
  font-size: 14px;
  transition: border-color 160ms ease;
}

.who:hover {
  border-color: var(--accent);
}

/* `.finder` is `SearchBox`'s own root class — a parent's scoped styles reach a
   child's root element, which is exactly what these need to do.

   The clock is the first thing to go: it is the one item in the bar nobody came
   for, and the field needs its width more. */
@media (max-width: 1100px) {
  .clock {
    display: none;
  }
}

@media (max-width: 860px) {
  nav {
    display: none;
  }
}

@media (max-width: 720px) {
  .finder {
    display: none;
  }

  .find {
    display: inline-flex;
  }
}
</style>
