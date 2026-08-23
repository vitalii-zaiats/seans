<script setup lang="ts">
/**
 * The way in.
 *
 * The same `POST /auth/login` every other client uses — this dashboard is not a
 * privileged door, it is an ordinary account that happens to have the role. The
 * check for that role is the API's; the message here only saves a person from
 * retyping a password that was right.
 */
import { ref } from 'vue'

import { useAuth } from '@/composables/useAuth'
import { mdiEye, mdiEyeOff } from '@/icons'

const auth = useAuth()

const email = ref('')
const password = ref('')
const reveal = ref(false)

function submit(): void {
  if (!email.value || !password.value) return
  void auth.signIn(email.value, password.value)
}
</script>

<template>
  <div class="gate">
    <v-card class="gate__card">
      <h1 class="gate__title">Super Movies</h1>
      <p class="gate__subtitle">Панель адміністратора</p>

      <v-form class="gate__form" @submit.prevent="submit">
        <v-text-field
          v-model="email"
          label="Пошта"
          type="email"
          autocomplete="username"
          autofocus
          :disabled="auth.busy.value"
        />
        <v-text-field
          v-model="password"
          label="Пароль"
          :type="reveal ? 'text' : 'password'"
          autocomplete="current-password"
          :append-inner-icon="reveal ? mdiEyeOff : mdiEye"
          :disabled="auth.busy.value"
          @click:append-inner="reveal = !reveal"
        />

        <v-alert v-if="auth.error.value" type="error" variant="tonal" density="compact">
          {{ auth.error.value }}
        </v-alert>

        <v-btn
          type="submit"
          variant="flat"
          color="primary"
          size="large"
          block
          :loading="auth.busy.value"
          :disabled="!email || !password"
        >
          Увійти
        </v-btn>
      </v-form>
    </v-card>
  </div>
</template>

<style scoped lang="scss">
.gate {
  min-height: 100dvh;
  display: grid;
  place-items: center;
  padding: 24px;

  &__card {
    width: 100%;
    max-width: 400px;
    padding: 32px;
  }

  &__title {
    margin: 0;
    font-size: 1.375rem;
    font-weight: 600;
    color: var(--chart-ink);
  }

  &__subtitle {
    margin: 4px 0 24px;
    color: var(--chart-muted);
    font-size: 0.875rem;
  }

  &__form {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
}
</style>
