<script setup lang="ts">
/**
 * An address with no code in it.
 *
 * Says what this page is for and where the code comes from, rather than
 * offering a box to type one into: the code is on a screen in the same room,
 * and the QR beside it is faster than any keyboard on a phone.
 */
</script>

<template>
  <v-container class="nowhere" max-width="480">
    <v-icon icon="$mdiTelevisionClassic" size="40" color="primary" />
    <h1 class="nowhere__title">Тут нічого підтверджувати</h1>
    <p class="text-medium-emphasis">
      Ця сторінка відкривається з QR-коду на екрані приставки. Знайдіть на ній
      «Створити акаунт зараз» і наведіть камеру на код.
    </p>
  </v-container>
</template>

<style scoped lang="scss">
.nowhere {
  padding-block: 4rem;
  text-align: center;
}

.nowhere__title {
  font-size: 1.375rem;
  font-weight: 600;
  margin-block: 0.75rem 0.5rem;
}
</style>
