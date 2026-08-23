<script setup lang="ts">
/**
 * The question the television asks on first run, asked once here.
 *
 * Three answers, none of which can be given wrongly — that is the point of
 * asking rather than deciding. What differs from the box is the third one: a
 * remote has no keyboard, so the wizard draws a QR code and lets a phone finish
 * the job. A browser has a keyboard, so it goes to the form.
 *
 * Honest about what an account buys today, which is not much: there is no watch
 * history in `contracts/openapi.json`, so the list and the resume stay in this
 * browser whatever is chosen here. Saying otherwise would be selling a
 * synchronisation that does not exist yet.
 */

const { answered, answer } = useWelcome()
const { token, keepGuest } = useAccount()
const router = useRouter()

/** Somebody already signed in has answered this by doing so. */
const open = computed(() => answered.value === null && !token.value)

// `app.vue` only renders this once the terms are accepted, so there is no
// second check here: two components deciding the same order would be two places
// to get it wrong.

const busy = ref(false)
const failed = ref<string | null>(null)

async function choose(choice: 'anonymous' | 'guest' | 'account'): Promise<void> {
  if (busy.value) return
  failed.value = null

  if (choice === 'guest') {
    busy.value = true
    try {
      await keepGuest()
    } catch (error) {
      // Nothing is recorded, so the question stands and can be answered again —
      // including with one of the two answers that need no server at all.
      failed.value = error instanceof ApiError ? error.message : 'Не вдалося'
      return
    } finally {
      busy.value = false
    }
  }

  answer(choice)
  if (choice === 'account') router.push('/account?new=1')
}

/**
 * Escape, or a click on the backdrop, is the anonymous answer.
 *
 * It is the one choice that asks nothing of anybody and sends nothing anywhere,
 * so reading a dismissal as that is the reading that cannot cost somebody
 * something they did not agree to. It is recorded, so the dialog does not
 * become a thing to dismiss on every visit — and «Акаунт» is one click away
 * whenever they change their mind.
 */
function dismiss(): void {
  if (!busy.value) choose('anonymous')
}

function onKey(event: KeyboardEvent): void {
  if (event.key === 'Escape') dismiss()
}

// The page behind a modal should not scroll under it.
watch(
  open,
  (showing) => {
    if (!import.meta.client) return
    document.body.style.overflow = showing ? 'hidden' : ''
    if (showing) window.addEventListener('keydown', onKey)
    else window.removeEventListener('keydown', onKey)
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  if (!import.meta.client) return
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onKey)
})

const tiles = [
  {
    id: 'anonymous',
    title: 'Продовжити анонімно',
    body: 'Нічого не залишає цей браузер. Жодного запиту про те, хто ви.',
  },
  {
    id: 'guest',
    title: 'Продовжити як гість',
    body:
      'Акаунт без пошти й пароля, який знає тільки цей браузер. Додасте їх пізніше — ' +
      'і це буде той самий акаунт, а не новий: переносити нічого не доведеться.',
  },
  {
    id: 'account',
    title: 'Створити акаунт',
    body: 'Пошта й пароль — щоб приставка та інший браузер упізнали вас. Відкриємо форму.',
  },
] as const
</script>

<template>
  <div v-if="open" class="welcome" @click.self="dismiss">
    <div class="welcome-sheet" role="dialog" aria-modal="true" aria-labelledby="welcome-title">
      <div class="mono kick">ПЕРШЕ ВІДКРИТТЯ</div>
      <h2 id="welcome-title">Акаунт</h2>
      <p class="lede">
        Каталог відкритий — дивитись можна й без нього. «Мій список» і «Продовжити дивитись»
        сьогодні лишаються в цьому браузері за будь-якої відповіді: історії перегляду на
        сервері поки що немає, а зʼявиться — вмикатимете її самі.
      </p>

      <div class="tiles">
        <button
          v-for="tile in tiles"
          :key="tile.id"
          type="button"
          class="tile"
          :disabled="busy"
          @click="choose(tile.id)"
        >
          <span class="head">
            <span class="name">{{ tile.title }}</span>
            <span class="mono go">→</span>
          </span>
          <span class="body">{{ tile.body }}</span>
        </button>
      </div>

      <div v-if="failed" class="mono bad">{{ failed }}</div>
      <div v-else class="mono foot">Змінити відповідь можна будь-коли в «Акаунт».</div>
    </div>
  </div>
</template>

<style scoped>
.welcome {
  position: fixed;
  inset: 0;
  z-index: 70;
  display: grid;
  place-items: center;
  padding: var(--gutter);
  background: color-mix(in srgb, #05060a 72%, transparent);
  backdrop-filter: blur(10px);
}

.welcome-sheet {
  width: min(640px, 100%);
  max-height: 100%;
  overflow-y: auto;
  padding: clamp(24px, 3vw, 40px);
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  /* On a dark ground elevation is an edge plus ambient darkness, never a stack
     of shadows. */
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
}

.kick {
  font-size: 11px;
  letter-spacing: 0.18em;
  color: var(--accent-300);
}

h2 {
  margin: 10px 0 0;
  font-weight: 500;
  font-size: clamp(28px, 3.4vw, 40px);
  letter-spacing: -0.01em;
}

.lede {
  margin: 12px 0 0;
  font-size: 15px;
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

.tiles {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: clamp(20px, 2.4vw, 28px) 0 0;
}

/* The box's own choice tile: a heading, a sentence saying what it means, and
   nothing hidden behind it. */
.tile {
  display: flex;
  flex-direction: column;
  gap: 6px;
  width: 100%;
  text-align: left;
  cursor: pointer;
  padding: 18px 20px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: transparent;
  transition:
    border-color 160ms ease,
    background 160ms ease;
}

.tile:hover:not(:disabled) {
  border-color: var(--accent);
  background: var(--accent-veil);
}

.tile:disabled {
  opacity: 0.45;
  cursor: default;
}

.head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px;
}

.name {
  font-family: var(--font-display);
  font-size: clamp(17px, 1.6vw, 20px);
}

.go {
  color: var(--neutral-600);
  font-size: 14px;
}

.tile:hover:not(:disabled) .go {
  color: var(--accent-300);
}

.body {
  font-size: 14px;
  line-height: 1.5;
  color: var(--neutral-500);
}

.foot,
.bad {
  display: block;
  margin-top: 18px;
  font-size: 12px;
  letter-spacing: 0.06em;
  color: var(--neutral-700);
}

.bad {
  color: var(--accent-300);
}
</style>
