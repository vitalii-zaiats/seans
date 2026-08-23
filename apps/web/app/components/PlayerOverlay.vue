<script setup lang="ts">
/**
 * The player, full-screen, over everything.
 *
 * The video itself is `HlsPlayer`; this is the frame around it — what is
 * playing, the way out, and the three states the opening can be in. Those three
 * are the point: the catalogue hands out an embed page rather than a stream, so
 * there is a real wait between pressing play and there being anything to play,
 * and a black rectangle during it reads as broken.
 */

const props = defineProps<{
  title: string
  meta: string
  art: string | null
  slug: string
  /** Null while the stream is still being worked out. */
  src: string | null
  startAt: number
  /** What went wrong, if anything did. */
  failed: string | null
}>()

const emit = defineEmits<{
  close: []
  progress: [{ position: number; duration: number }]
}>()

const player = ref<{
  toggle: () => void
  skip: (delta: number) => void
  where: () => { position: number; duration: number }
} | null>(null)

/**
 * Leaving, and saying where from — in that order.
 *
 * The order is the whole of it: closing clears what is playing, and a bookmark
 * reported after that has nothing to attach itself to. Vue's emits are
 * synchronous, so the parent has written the position down before it is asked
 * to forget the title.
 */
function leave(): void {
  const at = player.value?.where()
  if (at && at.duration > 0) emit('progress', at)
  emit('close')
}

function onKey(event: KeyboardEvent): void {
  // The native controls own the keyboard once the video has focus; these are
  // for the rest of the screen, and Escape is for both.
  if (event.key === 'Escape') {
    leave()
    return
  }
  if (!props.src) return
  if (event.key === ' ') {
    event.preventDefault()
    player.value?.toggle()
  } else if (event.key === 'ArrowRight') {
    player.value?.skip(30)
  } else if (event.key === 'ArrowLeft') {
    player.value?.skip(-30)
  }
}

onMounted(() => {
  window.addEventListener('keydown', onKey)
  // The page behind still scrolls under a fixed overlay, and a rail moving
  // about behind the controls is somebody's lost place.
  document.body.style.overflow = 'hidden'
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey)
  document.body.style.overflow = ''
})
</script>

<template>
  <div class="player" role="dialog" aria-modal="true" :aria-label="title">
    <div class="backdrop" :style="{ background: artBackground(slug) }">
      <img v-if="art" :src="art" alt="" />
    </div>
    <div class="scrim" />

    <div class="top">
      <div class="named">
        <div class="name">{{ title }}</div>
        <div class="mono meta">{{ meta }}</div>
      </div>
      <button type="button" class="shut" aria-label="Закрити" @click="leave">✕</button>
    </div>

    <div class="stage">
      <HlsPlayer
        v-if="src"
        ref="player"
        class="video"
        :src="src"
        :poster="art"
        :start="startAt"
        @progress="emit('progress', $event)"
        @ended="leave"
      />

      <div v-else-if="failed" class="waiting">
        <div class="mono bad">{{ failed }}</div>
        <button type="button" class="btn" @click="emit('close')">Закрити</button>
      </div>

      <div v-else class="waiting">
        <span class="dot" />
        <div class="mono">Шукаємо потік…</div>
        <p class="mono note">
          Каталог віддає сторінку плеєра, а не відео — сервер читає її й дістає доріжку.
        </p>
      </div>
    </div>

    <div v-if="src" class="mono hint">пробіл — пауза · ←→ 30 с · esc — вийти</div>
  </div>
</template>

<style scoped>
.player {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  flex-direction: column;
  background: #0b0c16;
}

.backdrop {
  position: absolute;
  inset: 0;
  background-size: cover;
  opacity: 0.35;
}

.backdrop img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.scrim {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--ground) 82%, transparent) 0%,
    color-mix(in srgb, var(--ground) 92%, transparent) 100%
  );
}

.top {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: clamp(12px, 2vw, 22px) var(--gutter);
}

.named {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 16px;
  min-width: 0;
}

.name {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: clamp(17px, 2vw, 26px);
}

.meta {
  font-size: clamp(11px, 1vw, 14px);
  color: var(--neutral-500);
}

.shut {
  flex: none;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  cursor: pointer;
  background: transparent;
  border: 1px solid var(--neutral-700);
  font-size: 16px;
  line-height: 1;
  transition:
    background 160ms ease,
    border-color 160ms ease;
}

.shut:hover {
  background: var(--accent-veil);
  border-color: var(--accent);
}

.stage {
  position: relative;
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.video {
  height: 100%;
}

.waiting {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 14px;
  padding: var(--gutter);
  text-align: center;
  font-size: 13px;
  letter-spacing: 0.1em;
  color: var(--neutral-500);
}

.note {
  max-width: 46ch;
  margin: 0;
  font-size: 12px;
  letter-spacing: 0;
  line-height: 1.6;
  color: var(--neutral-700);
}

.bad {
  color: var(--accent-300);
  letter-spacing: 0;
  font-size: 14px;
  max-width: 46ch;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--accent);
  animation: breathe 1.4s ease-in-out infinite;
}

@keyframes breathe {
  0%,
  100% {
    opacity: 0.35;
  }
  50% {
    opacity: 1;
  }
}

.hint {
  position: relative;
  padding: 0 var(--gutter) clamp(14px, 2vw, 24px);
  font-size: 12px;
  color: var(--neutral-700);
}
</style>
