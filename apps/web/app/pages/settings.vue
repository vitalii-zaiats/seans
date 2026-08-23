<script setup lang="ts">
/**
 * The look, and nothing else.
 *
 * The television's settings screen carries a great deal more — which rails to
 * show, which channel sources, how long before the idle screen — because those
 * are properties of a box. A browser tab has none of them: it is closed rather
 * than left idle, and the sections it shows are the ones the catalogue has.
 *
 * Scale is missing for the same sort of reason: a television is watched from a
 * sofa and has no zoom, while every browser has one under ⌘+ and does it
 * better than a stylesheet could.
 */

const theme = useTheme()

useHead({ title: 'Вигляд — Сеанс' })
</script>

<template>
  <div class="settings">
    <h1>Вигляд</h1>
    <p class="lede">
      Дві фарби, з яких зроблено все інше: рамки, підписи, панелі й підсвітка змішуються з
      них на місці. Вибір лишається в цьому браузері.
    </p>

    <section>
      <h2 class="label">Акцент</h2>
      <p class="what">Колір рамки фокуса, підписів і позначок</p>
      <div class="chips">
        <button
          v-for="one in ACCENTS"
          :key="one.color"
          type="button"
          class="chip"
          :class="{ on: theme.accent.value === one.color }"
          @click="theme.chooseAccent(one.color)"
        >
          <span class="dot" :style="{ background: one.color }" />
          {{ one.label }}
        </button>
      </div>
    </section>

    <section>
      <h2 class="label">Тло</h2>
      <p class="what">Ґрунт, на якому лежить увесь інтерфейс</p>
      <div class="chips">
        <button
          v-for="one in GROUNDS"
          :key="one.color"
          type="button"
          class="chip"
          :class="{ on: theme.ground.value === one.color }"
          @click="theme.chooseGround(one.color)"
        >
          <span class="dot ring" :style="{ background: one.color }" />
          {{ one.label }}
        </button>
      </div>
    </section>

    <section class="sample">
      <h2 class="label">Як це виглядає</h2>
      <div class="card">
        <div class="mono kick">ЗРАЗОК</div>
        <div class="name">Панель, підпис і дві кнопки</div>
        <p>
          Оце тіло тексту на панелі — щоб було видно, як обраний ґрунт тримає підняту
          поверхню, а акцент лишається лінією, а не заливкою.
        </p>
        <div class="row">
          <button type="button" class="btn btn-primary">Дивитись</button>
          <button type="button" class="btn">Про фільм</button>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.settings {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
  max-width: 900px;
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
}

.lede {
  max-width: 60ch;
  margin: 14px 0 clamp(28px, 4vw, 44px);
  font-size: 15px;
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

section + section {
  margin-top: clamp(28px, 4vw, 44px);
}

.what {
  margin: 8px 0 16px;
  font-size: 14px;
  color: var(--neutral-500);
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.chip {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
  padding: 12px 20px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  font-family: var(--font-body);
  font-size: 15px;
  color: var(--neutral-300);
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

.dot {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  flex: none;
}

/* A ground is often near-black, and a black circle on a dark panel is a hole
   rather than a swatch. */
.ring {
  box-shadow: inset 0 0 0 1px var(--neutral-700);
}

.sample .card {
  padding: clamp(20px, 2.6vw, 30px);
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  max-width: 560px;
}

.kick {
  font-size: 11px;
  letter-spacing: 0.18em;
  color: var(--accent-300);
}

.name {
  font-family: var(--font-display);
  font-size: 22px;
  margin: 10px 0 8px;
}

.sample p {
  margin: 0 0 20px;
  font-size: 15px;
  line-height: 1.6;
  color: var(--neutral-400);
}

.row {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}
</style>
