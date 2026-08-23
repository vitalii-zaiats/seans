<script setup lang="ts">
/**
 * The shell every screen sits in: the bar, the screen, the line at the foot.
 *
 * The account is read back here rather than on the screen that shows it —
 * whoever it belongs to is visible in the bar from the first paint, and a name
 * that appears three screens later reads as a bug.
 */

const { load } = useAccount()
const { blocked } = useTerms()
const { paint } = useTheme()

onMounted(() => {
  load()
  // The head script has already set these before the first paint. This is for
  // the state, which is read from the same storage — running it once keeps the
  // two in step without either needing to know about the other.
  paint()
})
</script>

<template>
  <div class="shell">
    <!--
      Nothing but the gate while the terms are unanswered — not the bar, not the
      foot. A dead interface behind a blur is still an interface: its links are
      unclickable but its search field is one Tab away, and focus behind a modal
      is the oldest way to make one leaky.
    -->
    <AppHeader v-if="!blocked" />
    <main>
      <!--
        Not rendered until the terms are accepted, rather than covered by the
        gate: a page that mounted would fetch a catalogue, start a rail and put
        a title on the screen behind the very window asking whether any of that
        may happen.
      -->
      <NuxtPage v-if="!blocked" />
    </main>
    <AppFooter v-if="!blocked" />
    <TermsGate v-if="blocked" />
    <!-- After the terms, and only ever once: the one question first run asks. -->
    <WelcomeDialog v-if="!blocked" />
  </div>
</template>

<style scoped>
.shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

main {
  flex: 1;
}
</style>
