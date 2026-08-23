<script setup lang="ts">
/**
 * What a screen says when it has nothing to show yet, nothing to show at all,
 * or a reason it cannot.
 *
 * One component for the three because they are one sentence in three moods, and
 * a screen that spells each of them out separately grows three ways for them
 * to disagree.
 */

defineProps<{
  loading?: boolean
  error?: string | null
  /** Shown when neither of the above and the slot's list came back empty. */
  empty?: string | null
}>()
</script>

<template>
  <div v-if="loading" class="note mono">
    <span class="dot" />Завантажуємо…
  </div>
  <div v-else-if="error" class="note mono bad">{{ error }}</div>
  <div v-else-if="empty" class="note mono">{{ empty }}</div>
</template>

<style scoped>
.note {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 22px var(--gutter);
  font-size: 13px;
  letter-spacing: 0.1em;
  color: var(--neutral-600);
}

.bad {
  color: var(--accent-300);
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
</style>
