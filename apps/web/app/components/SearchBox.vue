<script setup lang="ts">
/**
 * Search, in the bar.
 *
 * A catalogue is the sort of thing people arrive at with a name already in
 * mind, and a page of its own put two clicks in front of that. So the field is
 * where the eye already is, and the answers drop under it — first six, with the
 * way to the rest at the foot of the panel.
 *
 * The page still exists and is still where Enter goes: a grid of forty is a
 * different thing from a list of six, `?q=` is an address somebody can send,
 * and on a narrow screen there is no room in the bar for any of this.
 */

const search = useSearch({ limit: 6, wait: 200 })
const router = useRouter()

const field = ref<HTMLInputElement | null>(null)
const box = ref<HTMLElement | null>(null)
const focused = ref(false)

/** Open only when there is something to show for what is typed. */
const open = computed(
  () => focused.value && search.term.value.trim().length >= 2 && (search.hits.value.length > 0 || search.asked.value || search.busy.value),
)

function submit(): void {
  const term = search.term.value.trim()
  if (!term) return
  router.push({ path: '/search', query: { q: term } })
  close()
}

function goto(slug: string): void {
  router.push(`/title/${slug}`)
  close()
}

function close(): void {
  focused.value = false
  field.value?.blur()
}

function onKey(event: KeyboardEvent): void {
  if (event.key === 'Escape') {
    // First press closes the panel, a second clears the field: the same order
    // a browser's own find bar uses.
    if (open.value) close()
    else search.clear()
  }
}

/**
 * A click anywhere else closes the panel.
 *
 * `blur` would be the obvious hook and is the wrong one: clicking a result *is*
 * a blur, and the panel would be gone before the click landed on it.
 */
function onClickOutside(event: MouseEvent): void {
  if (!box.value?.contains(event.target as Node)) focused.value = false
}

onMounted(() => document.addEventListener('click', onClickOutside))
onBeforeUnmount(() => document.removeEventListener('click', onClickOutside))
</script>

<template>
  <div ref="box" class="finder">
    <input
      ref="field"
      :value="search.term.value"
      class="field"
      type="search"
      placeholder="Пошук"
      aria-label="Пошук по каталогу"
      @input="search.type(($event.target as HTMLInputElement).value)"
      @focus="focused = true"
      @keydown="onKey"
      @keydown.enter="submit"
    />

    <div v-if="open" class="panel">
      <button
        v-for="hit in search.hits.value"
        :key="hit.card.slug"
        type="button"
        class="hit"
        @click="goto(hit.card.slug)"
      >
        <span class="art thumb" :style="{ background: artBackground(hit.card.slug) }">
          <img v-if="hit.card.poster_url" :src="hit.card.poster_url" alt="" loading="lazy" />
        </span>
        <span class="what">
          <span class="name">{{ hit.card.name }}</span>
          <span class="mono meta">{{ cardMeta(hit.card) }}</span>
        </span>
      </button>

      <div v-if="search.busy.value && !search.hits.value.length" class="mono empty">Шукаємо…</div>
      <div v-else-if="search.failed.value" class="mono empty bad">{{ search.failed.value }}</div>
      <div v-else-if="!search.hits.value.length" class="mono empty">Нічого не знайшлось</div>

      <button v-if="search.hits.value.length" type="button" class="all mono" @click="submit">
        Усі результати →
      </button>
    </div>
  </div>
</template>

<style scoped>
.finder {
  position: relative;
  flex: 0 1 320px;
  min-width: 140px;
}

.field {
  width: 100%;
  padding: 8px 14px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: color-mix(in srgb, var(--surface) 70%, transparent);
  color: var(--text);
  font-family: var(--font-body);
  font-size: 14px;
  transition:
    border-color 160ms ease,
    background 160ms ease;
}

.field:hover {
  border-color: var(--neutral-700);
}

.field:focus {
  outline: none;
  border-color: var(--accent);
  background: var(--surface);
}

.field::placeholder {
  color: var(--neutral-600);
}

.panel {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  width: min(420px, 78vw);
  padding: 6px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6);
}

.hit {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  text-align: left;
  cursor: pointer;
  padding: 8px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  transition: background 140ms ease;
}

.hit:hover {
  background: var(--accent-veil);
}

.thumb {
  flex: none;
  width: 34px;
  aspect-ratio: 2 / 3;
  border-radius: 4px;
  box-shadow: none;
}

.thumb img {
  position: absolute;
  inset: 0;
}

.what {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.name {
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.meta {
  font-size: 11px;
  color: var(--neutral-600);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.empty {
  padding: 14px 10px;
  font-size: 12px;
  letter-spacing: 0.08em;
  color: var(--neutral-600);
}

.bad {
  color: var(--accent-300);
}

.all {
  display: block;
  width: 100%;
  text-align: left;
  cursor: pointer;
  margin-top: 4px;
  padding: 10px;
  border: 0;
  border-top: 1px solid var(--hairline);
  border-radius: 0 0 6px 6px;
  background: transparent;
  font-size: 12px;
  letter-spacing: 0.08em;
  color: var(--neutral-500);
  transition: color 140ms ease;
}

.all:hover {
  color: var(--accent-300);
}
</style>
