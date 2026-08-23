<script setup lang="ts">
/**
 * The whole of a search: a grid of forty rather than the six the bar drops
 * under itself.
 *
 * Still here now that the bar has a field, and for three reasons: `?q=` is an
 * address that can be sent and reloaded, a narrow screen has no room in the bar
 * for any of this, and a page of results is a different thing to read than a
 * list of suggestions.
 */

const route = useRoute()
const router = useRouter()

const search = useSearch({ limit: 40 })

/** The address is what this page is about, so it is what drives the query. */
watch(
  () => route.query.q,
  (q) => {
    const term = typeof q === 'string' ? q : ''
    if (term !== search.term.value) {
      search.term.value = term
      search.run(term)
    }
  },
  { immediate: true },
)

function typed(value: string): void {
  search.type(value)
  // Replaced rather than pushed: every keystroke would otherwise be its own
  // step back.
  router.replace({ query: value ? { q: value } : {} })
}

useHead({ title: 'Пошук — Сеанс' })
</script>

<template>
  <div class="search">
    <h1>Пошук</h1>
    <input
      :value="search.term.value"
      class="input field"
      type="search"
      autofocus
      placeholder="Назва фільму або серіалу"
      aria-label="Пошук"
      @input="typed(($event.target as HTMLInputElement).value)"
    />

    <div v-if="search.hits.value.length" class="grid">
      <TitleCard v-for="hit in search.hits.value" :key="hit.card.slug" :card="hit.card" />
    </div>

    <StatusNote
      :loading="search.busy.value && !search.hits.value.length"
      :error="search.failed.value"
      :empty="
        search.asked.value && !search.busy.value && !search.hits.value.length
          ? 'Нічого не знайшлось'
          : null
      "
    />

    <p v-if="!search.term.value" class="mono nudge">Двох літер вистачить, щоб почати.</p>
  </div>
</template>

<style scoped>
.search {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
  margin-bottom: clamp(18px, 2.4vw, 28px);
}

.field {
  max-width: 640px;
  font-size: clamp(16px, 1.4vw, 20px);
  padding: 14px 18px;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 200px), 1fr));
  gap: clamp(12px, 1.6vw, 24px);
  margin-top: clamp(24px, 3vw, 40px);
}

.nudge {
  margin-top: 20px;
  font-size: 13px;
  color: var(--neutral-700);
}
</style>
