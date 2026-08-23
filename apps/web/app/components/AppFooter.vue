<script setup lang="ts">
/** The line at the foot: what this is, and what day it is. */

const today = new Date().toLocaleDateString('uk-UA', {
  weekday: 'long',
  day: 'numeric',
  month: 'long',
})
</script>

<template>
  <footer class="foot mono">
    <div>SEANS — WEB</div>
    <nav>
      <NuxtLink to="/settings">Вигляд</NuxtLink>
      <NuxtLink to="/terms">Умови</NuxtLink>
      <NuxtLink to="/privacy">Приватність</NuxtLink>
      <NuxtLink to="/rights">Правовласникам</NuxtLink>
      <NuxtLink to="/downloads">Завантажити</NuxtLink>
    </nav>
    <div>{{ today.toUpperCase() }}</div>
  </footer>
</template>

<style scoped>
.foot {
  display: flex;
  flex-wrap: wrap;
  gap: 12px 32px;
  align-items: baseline;
  justify-content: space-between;
  padding: 28px var(--gutter) 48px;
  margin-top: clamp(36px, 6vw, 72px);
  border-top: 1px solid var(--hairline);
  font-size: 12px;
  letter-spacing: 0.1em;
  color: var(--neutral-700);
}

nav {
  display: flex;
  flex-wrap: wrap;
  gap: 12px 24px;
}

nav a {
  color: var(--neutral-600);
  transition: color 160ms ease;
}

nav a:hover {
  color: var(--text);
}
</style>
