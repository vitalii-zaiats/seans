<script setup lang="ts">
/**
 * The page a QR code opens.
 *
 * One question, asked once: is that television yours, and do you mean to sign
 * it in? Everything else on screen is there to let somebody answer it — the
 * name the box gave itself, so they can tell their own living room from
 * somebody else's, and the time left, so nobody sits waiting on a button that
 * will refuse them.
 *
 * What this page never touches is the television's own secret. Approving says
 * only "yes, as me"; the box collects the session itself, with something that
 * never left it. So a code approved by the wrong person still hands the account
 * to the box that asked for it, and to nothing else.
 */

import { onMounted, watch } from 'vue'

import SignInCard from '@/components/SignInCard.vue'
import { useAuth } from '@/composables/useAuth'
import { usePairing } from '@/composables/usePairing'

const props = defineProps<{ code: string }>()

const { account, signedIn, checking, token, signOut, restore } = useAuth()
const { link, stage, error, busy, seconds, countdown, load, approve } = usePairing(
  props.code.toUpperCase(),
)

onMounted(async () => {
  // Both at once: the code is worth checking whether or not anybody is signed
  // in, and a phone that has been here before should not watch a spinner while
  // its own token is confirmed.
  await Promise.all([restore(), load()])
})

// A phone that signs in while the page is open has just answered the only
// question that stood in the way. Nothing is approved automatically — that is
// the one thing this page must not do on somebody's behalf.
watch(signedIn, (now) => {
  if (now) error.value = null
})

/** Under a minute left is worth pointing out rather than merely counting. */
const RUNNING_OUT = 60

function confirm(): void {
  if (token.value !== null) void approve(token.value)
}
</script>

<template>
  <v-container class="pair" max-width="480">
    <header class="pair__head">
      <v-icon icon="$mdiTelevisionClassic" size="40" color="primary" />
      <h1 class="pair__title">Вхід на приставку</h1>
      <p class="pair__code">{{ props.code.toUpperCase() }}</p>
    </header>

    <!-- Waiting on the server for the code itself. -->
    <v-card v-if="stage === 'loading'" class="pa-6 text-center">
      <v-progress-circular indeterminate color="primary" />
      <p class="mt-4 text-medium-emphasis">Перевіряємо код…</p>
    </v-card>

    <!-- The three ways a code stops meaning anything. Each says which one it
         was, because "спробуйте ще раз" is different advice from "цей код уже
         використали". -->
    <v-card v-else-if="stage === 'missing'" class="pa-6">
      <h2 class="text-h6 mb-2">Такого коду немає</h2>
      <p class="text-medium-emphasis">
        Він міг застаріти або бути введений з помилкою. Відкрийте на приставці
        «Створити акаунт зараз» ще раз — вона покаже новий.
      </p>
    </v-card>

    <v-card v-else-if="stage === 'expired'" class="pa-6">
      <h2 class="text-h6 mb-2">Код застарів</h2>
      <p class="text-medium-emphasis">
        Коди живуть кілька хвилин, щоб той, що лишився на екрані в спільній
        квартирі, перестав щось означати сам собою. Попросіть приставку показати
        новий.
      </p>
    </v-card>

    <v-card v-else-if="stage === 'taken'" class="pa-6">
      <h2 class="text-h6 mb-2">Код уже використали</h2>
      <p class="text-medium-emphasis">
        Цю приставку підтвердив хтось інший. Якщо це були не ви — попросіть її
        показати новий код.
      </p>
    </v-card>

    <!-- Done. -->
    <v-card v-else-if="stage === 'approved'" class="pa-6 text-center">
      <v-icon icon="$mdiCheckCircleOutline" size="56" color="success" />
      <h2 class="text-h6 mt-4 mb-2">Готово</h2>
      <p class="text-medium-emphasis">
        Приставка входить у ваш акаунт. Можна закрити цю сторінку — далі вона
        впорається сама.
      </p>
    </v-card>

    <!-- Something else. Rare, and worth saying plainly rather than dressing up. -->
    <v-card v-else-if="stage === 'failed'" class="pa-6">
      <h2 class="text-h6 mb-2">Не вдалося</h2>
      <p class="text-medium-emphasis">{{ error }}</p>
      <v-btn class="mt-4" variant="tonal" color="primary" @click="load">Спробувати ще</v-btn>
    </v-card>

    <!-- The question itself. -->
    <template v-else>
      <v-card class="pa-6 mb-4">
        <p class="text-medium-emphasis mb-1">Підтвердити вхід для</p>
        <p class="text-h6">{{ link?.device_name ?? 'приставки' }}</p>

        <div class="pair__clock" :class="{ 'pair__clock--soon': seconds <= RUNNING_OUT }">
          <v-icon icon="$mdiClockOutline" size="16" />
          <span>лишилось {{ countdown }}</span>
        </div>

        <v-alert type="info" variant="tonal" density="compact" class="mt-4">
          Підтверджуйте, лише якщо цей код зараз показує ваш власний екран.
        </v-alert>
      </v-card>

      <v-card v-if="checking" class="pa-6 text-center">
        <v-progress-circular indeterminate color="primary" size="24" />
      </v-card>

      <SignInCard v-else-if="!signedIn" />

      <v-card v-else class="pa-6">
        <p class="text-medium-emphasis mb-1">Ви увійшли як</p>
        <p class="text-body-1 mb-4">{{ account?.email ?? account?.display_name }}</p>

        <v-btn
          variant="flat"
          color="primary"
          size="large"
          block
          :loading="busy"
          @click="confirm"
        >
          Підтвердити
        </v-btn>
        <v-btn class="mt-2" size="small" block @click="signOut">Це не мій акаунт</v-btn>
      </v-card>
    </template>
  </v-container>
</template>

<style scoped lang="scss">
.pair {
  padding-block: 2.5rem 3rem;
}

.pair__head {
  text-align: center;
  margin-bottom: 1.5rem;
}

.pair__title {
  font-size: 1.5rem;
  font-weight: 600;
  margin-block: 0.75rem 0.5rem;
}

/* Spaced and monospaced, because it is read off a screen across a room and
   compared character by character. */
.pair__code {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 1.75rem;
  letter-spacing: 0.35em;
  text-indent: 0.35em;
  color: rgb(var(--v-theme-primary));
}

.pair__clock {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-top: 1rem;
  font-size: 0.875rem;
  opacity: 0.7;
}

.pair__clock--soon {
  color: rgb(var(--v-theme-warning));
  opacity: 1;
}
</style>
