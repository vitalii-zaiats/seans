<script setup lang="ts">
/**
 * What this browser saved, and what it has half-watched.
 *
 * Both are read out of `localStorage` and looked up by slug, so this page is
 * empty in a different browser and on a different machine — which is the whole
 * truth about it, and the reason the empty state says so rather than offering
 * a sign-in that would not help.
 */

import type { Card } from '~/types/api'

const library = useLibrary()

const wanted = computed(() => [
  ...new Set([...library.list.value, ...library.resumable.value.map((one) => one.slug)]),
])

const { data, pending, error } = await useAsyncData(
  'my-list',
  async () => {
    if (wanted.value.length === 0) return new Map<string, Card>()
    const cards = await api.cards(wanted.value)
    return new Map(cards.items.map((card) => [card.slug, card]))
  },
  { watch: [wanted] },
)

const saved = computed(() =>
  library.list.value.flatMap((slug) => {
    const card = data.value?.get(slug)
    return card ? [card] : []
  }),
)

const resume = computed(() =>
  library.resumable.value.flatMap((entry) => {
    const card = data.value?.get(entry.slug)
    return card ? [{ card, entry }] : []
  }),
)

useHead({ title: 'Мій список — Сеанс' })
</script>

<template>
  <div class="list">
    <h1>Мій список</h1>

    <section v-if="resume.length" class="block">
      <h2 class="label">Продовжити дивитись</h2>
      <div class="grid wide">
        <div v-for="one in resume" :key="one.card.slug" class="held">
          <TitleCard :card="one.card" wide :resume="fractionOf(one.entry)" />
          <button
            type="button"
            class="btn btn-ghost drop"
            @click="library.forget(one.card.slug)"
          >
            Прибрати
          </button>
        </div>
      </div>
    </section>

    <section class="block">
      <h2 class="label">Збережене</h2>
      <div v-if="saved.length" class="grid">
        <TitleCard v-for="card in saved" :key="card.slug" :card="card" />
      </div>
      <StatusNote
        :loading="pending && !saved.length && wanted.length > 0"
        :error="error ? 'Не вдалося дістати картки' : null"
        :empty="
          !pending && !saved.length
            ? 'Тут порожньо. Список живе в цьому браузері — кнопка «До списку» на сторінці тайтла кладе його сюди.'
            : null
        "
      />
    </section>
  </div>
</template>

<style scoped>
.list {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
  margin-bottom: clamp(24px, 3vw, 40px);
}

.block + .block {
  margin-top: clamp(32px, 4vw, 56px);
}

.block .label {
  margin-bottom: 16px;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 200px), 1fr));
  gap: clamp(12px, 1.6vw, 24px);
}

.grid.wide {
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr));
}

.held {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.drop {
  align-self: flex-start;
  padding: 4px 10px;
  font-family: var(--font-mono);
  font-size: 11px;
  letter-spacing: 0.1em;
  color: var(--neutral-600);
}

/* The note carries the page's own gutter, and inside a section it is already
   in one. */
.block :deep(.note) {
  padding-inline: 0;
}
</style>
