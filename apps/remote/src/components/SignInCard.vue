<script setup lang="ts">
/**
 * Signing in, or making an account, in one card.
 *
 * Two tabs rather than two screens: whoever is here arrived from a camera
 * pointed at a television, and sending them somewhere else to come back is how
 * a thirty-second job becomes a minute of hunting for the right page.
 *
 * Registration takes no display name. One less box on a phone keyboard, and the
 * server names the account after the email until somebody says otherwise.
 */

import { computed, ref, watch } from 'vue'

import { useAuth } from '@/composables/useAuth'

const { busy, error, signIn, signUp, clearError } = useAuth()

const tab = ref<'in' | 'up'>('in')
const email = ref('')
const password = ref('')
const showPassword = ref(false)

/** The server's floor, said here so nobody types eight characters to find out. */
const MIN_PASSWORD = 8

const registering = computed(() => tab.value === 'up')

const canSubmit = computed(
  () =>
    email.value.includes('@') &&
    password.value.length >= (registering.value ? MIN_PASSWORD : 1),
)

// A refusal belongs to the attempt that earned it. Carrying "wrong email or
// password" across to the registration tab would be answering a question
// nobody asked.
watch(tab, () => clearError())

async function submit(): Promise<void> {
  if (!canSubmit.value || busy.value) return
  const ok = registering.value
    ? await signUp(email.value.trim(), password.value)
    : await signIn(email.value.trim(), password.value)
  if (ok) password.value = ''
}
</script>

<template>
  <v-card>
    <v-tabs v-model="tab" grow color="primary">
      <v-tab value="in">Увійти</v-tab>
      <v-tab value="up">Створити акаунт</v-tab>
    </v-tabs>

    <v-card-text>
      <v-form @submit.prevent="submit">
        <v-text-field
          v-model="email"
          label="Пошта"
          type="email"
          autocomplete="email"
          inputmode="email"
          autocapitalize="none"
          spellcheck="false"
          class="mb-3"
        />
        <v-text-field
          v-model="password"
          label="Пароль"
          :type="showPassword ? 'text' : 'password'"
          :autocomplete="registering ? 'new-password' : 'current-password'"
          :hint="registering ? `Щонайменше ${MIN_PASSWORD} символів` : undefined"
          :persistent-hint="registering"
          :append-inner-icon="showPassword ? '$mdiEyeOff' : '$mdiEye'"
          @click:append-inner="showPassword = !showPassword"
        />

        <v-alert v-if="error" type="error" variant="tonal" class="mt-4" density="compact">
          {{ error }}
        </v-alert>

        <v-btn
          type="submit"
          variant="flat"
          color="primary"
          size="large"
          block
          class="mt-4"
          :loading="busy"
          :disabled="!canSubmit"
        >
          {{ registering ? 'Створити' : 'Увійти' }}
        </v-btn>
      </v-form>
    </v-card-text>
  </v-card>
</template>
