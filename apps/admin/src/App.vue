<script setup lang="ts">
/**
 * The shell: a bar, a theme toggle, and the one decision this app makes —
 * whether the person looking is allowed to see the numbers.
 */
import { onMounted } from 'vue'
import { useTheme } from 'vuetify'

import SignInCard from '@/components/SignInCard.vue'
import { useAuth } from '@/composables/useAuth'
import { mdiLogout, mdiWeatherNight, mdiWeatherSunny } from '@/icons'
import { rememberTheme } from '@/plugins/vuetify'
import DashboardView from '@/views/DashboardView.vue'

const auth = useAuth()
const theme = useTheme()

function flip(): void {
  const next = theme.global.current.value.dark ? 'light' : 'dark'
  theme.change(next)
  rememberTheme(next)
}

onMounted(() => void auth.restore())
</script>

<template>
  <v-app>
    <!-- A stored token is checked before anything is drawn: showing the login
         form for the half-second that takes would flash it at somebody who is
         already signed in. -->
    <v-main v-if="auth.restoring.value">
      <div class="splash">
        <v-progress-circular indeterminate />
      </div>
    </v-main>

    <template v-else-if="auth.authorised.value">
      <v-app-bar flat border density="comfortable">
        <v-app-bar-title class="shell__brand">Super Movies</v-app-bar-title>

        <v-spacer />

        <span class="shell__who">{{ auth.account.value?.email ?? auth.account.value?.display_name }}</span>

        <v-btn
          :icon="theme.global.current.value.dark ? mdiWeatherSunny : mdiWeatherNight"
          aria-label="Перемкнути тему"
          @click="flip"
        />
        <v-btn :icon="mdiLogout" aria-label="Вийти" @click="auth.signOut" />
      </v-app-bar>

      <v-main>
        <DashboardView />
      </v-main>
    </template>

    <v-main v-else>
      <SignInCard />
    </v-main>
  </v-app>
</template>

<style scoped lang="scss">
.splash {
  min-height: 100dvh;
  display: grid;
  place-items: center;
}

.shell {
  &__brand {
    font-size: 1rem;
    font-weight: 600;
  }

  &__who {
    font-size: 0.8125rem;
    color: var(--chart-muted);
    margin-right: 8px;

    @include narrow {
      display: none;
    }
  }
}
</style>
