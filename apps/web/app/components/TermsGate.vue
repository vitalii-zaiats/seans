<script setup lang="ts">
/**
 * The one thing that comes before everything.
 *
 * Not dismissible: no Escape, no click on the backdrop, no way past it but the
 * button. Everything else on this site can be shrugged off — this cannot, which
 * is the whole point of it existing.
 *
 * `app.vue` does not render the page behind it, so nothing is fetched and no
 * screen is running while this is up. A modal that merely covered a working app
 * would be a curtain, not a gate.
 *
 * The three documents stay reachable: agreeing to a text you were not allowed
 * to read would be worth nothing, so `useTerms` lets those routes through.
 */

const { declined, accept, decline, reconsider } = useTerms()

const points = [
  'Це оболонка над стороннім каталогом. Ані фільмів, ані серіалів тут не зберігається — ми показуємо описи й ведемо до чужих плеєрів.',
  'Сервіс безкоштовний і надається як є: без гарантій доступності, повноти каталогу чи того, що конкретний тайтл відкриється.',
  'За те, що ви відкриваєте за посиланнями третіх сторін, відповідаєте ви — включно з тим, чи законно це там, де ви є.',
  'Історію перегляду ми не збираємо без вашого дозволу: сьогодні список і час зупинки лежать лише у вашому браузері, а синхронізація, якщо зʼявиться, буде окремим вибором.',
]

// The page behind is not rendered at all, but the document still scrolls.
onMounted(() => (document.body.style.overflow = 'hidden'))
onBeforeUnmount(() => (document.body.style.overflow = ''))
</script>

<template>
  <div class="gate">
    <div class="gate-sheet" role="dialog" aria-modal="true" aria-labelledby="terms-title">
      <div class="word">SEANS</div>

      <template v-if="!declined">
        <div class="mono kick">УМОВИ КОРИСТУВАННЯ</div>
        <h2 id="terms-title">Перш ніж почати</h2>

        <ul class="points">
          <li v-for="(point, index) in points" :key="index">
            <span class="mono num">{{ String(index + 1).padStart(2, '0') }}</span>
            <span>{{ point }}</span>
          </li>
        </ul>

        <p class="full">
          Повний текст: <NuxtLink to="/terms">умови</NuxtLink> ·
          <NuxtLink to="/privacy">приватність</NuxtLink> ·
          <NuxtLink to="/rights">правовласникам</NuxtLink>. Відкриються прямо звідси —
          повернетесь, і це вікно буде на місці.
        </p>

        <div class="row">
          <button type="button" class="btn btn-primary" @click="accept">
            Приймаю
          </button>
          <button type="button" class="btn" @click="decline">Не приймаю</button>
        </div>
      </template>

      <template v-else>
        <div class="mono kick">УМОВИ НЕ ПРИЙНЯТО</div>
        <h2 id="terms-title">Тоді на цьому все</h2>
        <p class="full">
          Без згоди з умовами користуватись сервісом не можна — це не спосіб натиснути на
          вас, просто інакше незрозуміло, на яких підставах він працює. Нічого не записано:
          ваш браузер у тому ж стані, що й до відкриття сторінки.
        </p>
        <div class="row">
          <button type="button" class="btn" @click="reconsider">Повернутись до умов</button>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.gate {
  position: fixed;
  inset: 0;
  z-index: 90;
  display: grid;
  place-items: center;
  padding: var(--gutter);
  background: color-mix(in srgb, #05060a 78%, transparent);
  backdrop-filter: blur(12px);
}

.gate-sheet {
  width: min(680px, 100%);
  max-height: 100%;
  overflow-y: auto;
  padding: clamp(24px, 3vw, 40px);
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
}

/* The bar is not on screen while this is up, so the mark comes with the sheet:
   it should be obvious whose terms these are. */
.word {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 15px;
  letter-spacing: 0.22em;
  margin-bottom: 22px;
  color: var(--neutral-500);
}

.kick {
  font-size: 11px;
  letter-spacing: 0.18em;
  color: var(--accent-300);
}

h2 {
  margin: 10px 0 0;
  font-weight: 500;
  font-size: clamp(26px, 3.2vw, 38px);
  letter-spacing: -0.01em;
}

.points {
  list-style: none;
  margin: clamp(18px, 2.4vw, 26px) 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.points li {
  display: flex;
  gap: 14px;
  font-size: 15px;
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

.num {
  flex: none;
  font-size: 11px;
  letter-spacing: 0.12em;
  color: var(--neutral-700);
  padding-top: 4px;
}

.full {
  margin: 22px 0 0;
  font-size: 14px;
  line-height: 1.7;
  color: var(--neutral-500);
}

.full a {
  color: var(--accent-300);
  border-bottom: 1px solid color-mix(in srgb, var(--accent) 40%, transparent);
}

.full a:hover {
  border-bottom-color: var(--accent);
}

.row {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 26px;
}
</style>
