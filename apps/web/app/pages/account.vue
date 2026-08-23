<script setup lang="ts">
/**
 * The account, as a form.
 *
 * The television shows a QR code here because a remote control has no keyboard.
 * A browser has one, so this is the shorter way to the same place: an email and
 * a password, on this machine, with no second device involved.
 *
 * Nothing on the site needs an account — the catalogue is open and the two
 * lists are this browser's — so this page is an offer, and says as much.
 */

const { account, token, checked, load, claim, signIn, register, signOut, forget } = useAccount()
const welcome = useWelcome()

/**
 * Signing in is the usual reason to be here, so it is the tab that opens —
 * unless the first-run dialog sent somebody here to make an account, which is
 * what `?new=1` says.
 */
const mode = ref<'in' | 'up'>(useRoute().query.new ? 'up' : 'in')
const email = ref('')
const password = ref('')
const name = ref('')
const busy = ref(false)
const failed = ref<string | null>(null)

onMounted(load)

/**
 * One form, three things it can be doing.
 *
 * A guest gets `claim` rather than `register`, and the difference is not
 * cosmetic: registering would open a second account and leave the guest — with
 * whatever the server has tied to it — behind and unreachable.
 */
async function submit(): Promise<void> {
  busy.value = true
  failed.value = null
  try {
    if (guest.value) await claim(email.value, password.value, name.value || undefined)
    else if (mode.value === 'in') await signIn(email.value, password.value)
    else await register(email.value, password.value, name.value || undefined)
    password.value = ''
  } catch (error) {
    failed.value = error instanceof ApiError ? error.message : 'Не вдалося'
  } finally {
    busy.value = false
  }
}

/** Signed in, but with nothing to sign in *with* — the state `claim` is for. */
const guest = computed(() => account.value?.is_guest ?? false)

/**
 * Deleting the account, behind a second press.
 *
 * There is no undo on the server: the row goes and every session with it. A
 * dialog would be the usual answer; a button that changes its own label is the
 * smaller one and reads the same — nothing happens on the first press.
 */
const armed = ref(false)

async function remove(): Promise<void> {
  if (!armed.value) {
    armed.value = true
    return
  }
  busy.value = true
  failed.value = null
  try {
    await forget()
    armed.value = false
  } catch (error) {
    failed.value = error instanceof ApiError ? error.message : 'Не вдалося видалити'
  } finally {
    busy.value = false
  }
}

useHead({ title: 'Акаунт — Сеанс' })
</script>

<template>
  <div class="account">
    <h1>Акаунт</h1>

    <div v-if="account && !guest" class="card">
      <div class="mono label-sm">ВИ УВІЙШЛИ ЯК</div>
      <div class="who">{{ account.display_name }}</div>
      <div class="mono mail">{{ account.email ?? '—' }}</div>
      <div class="row">
        <button type="button" class="btn" @click="signOut">Вийти</button>
        <button type="button" class="btn danger" :disabled="busy" @click="remove">
          {{ armed ? 'Точно видалити?' : 'Видалити акаунт' }}
        </button>
      </div>
      <p v-if="armed" class="mono hint">
        Акаунт і всі його сесії зникнуть із сервера назавжди. «Мій список» і «Продовжити
        дивитись» лишаться — вони в цьому браузері, а не там.
      </p>
      <div v-if="failed" class="mono bad">{{ failed }}</div>
    </div>

    <div v-else-if="guest" class="card">
      <div class="mono label-sm">ВИ ЗАРАЗ ГІСТЬ</div>
      <div class="who">{{ account?.display_name }}</div>
      <p class="explain">
        Гість — це вже акаунт, просто без пошти й пароля, тож дістатись до нього можна лише
        з цього браузера. Додайте їх — і це буде <em>той самий</em> акаунт: нічого не
        переноситься й нічого не створюється заново, тому все, що до нього привʼязано,
        лишається на місці. Реєстрація натомість завела б другий і покинула цей.
      </p>

      <form @submit.prevent="submit">
        <label>
          <span class="label-sm">ПОШТА</span>
          <input v-model="email" class="input" type="email" required autocomplete="email" />
        </label>
        <label>
          <span class="label-sm">ПАРОЛЬ</span>
          <input
            v-model="password"
            class="input"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
          />
        </label>
        <label>
          <span class="label-sm">ІМʼЯ (НЕОБОВʼЯЗКОВО)</span>
          <input v-model="name" class="input" type="text" autocomplete="nickname" />
        </label>

        <div v-if="failed" class="mono bad">{{ failed }}</div>

        <div class="row">
          <button type="submit" class="btn btn-primary" :disabled="busy">
            {{ busy ? 'Хвилинку…' : 'Зберегти акаунт' }}
          </button>
          <button type="button" class="btn" :disabled="busy" @click="signOut">
            Вийти й лишитись анонімним
          </button>
        </div>
      </form>
    </div>

    <div v-else class="card">
      <div class="tabs">
        <button
          type="button"
          class="tab"
          :class="{ on: mode === 'in' }"
          @click="mode = 'in'"
        >
          Вхід
        </button>
        <button
          type="button"
          class="tab"
          :class="{ on: mode === 'up' }"
          @click="mode = 'up'"
        >
          Реєстрація
        </button>
      </div>

      <form @submit.prevent="submit">
        <label>
          <span class="label-sm">ПОШТА</span>
          <input v-model="email" class="input" type="email" required autocomplete="email" />
        </label>
        <label>
          <span class="label-sm">ПАРОЛЬ</span>
          <input
            v-model="password"
            class="input"
            type="password"
            required
            minlength="8"
            :autocomplete="mode === 'in' ? 'current-password' : 'new-password'"
          />
        </label>
        <label v-if="mode === 'up'">
          <span class="label-sm">ІМʼЯ (НЕОБОВʼЯЗКОВО)</span>
          <input v-model="name" class="input" type="text" autocomplete="nickname" />
        </label>

        <div v-if="failed" class="mono bad">{{ failed }}</div>

        <button type="submit" class="btn btn-primary" :disabled="busy">
          {{ busy ? 'Хвилинку…' : mode === 'in' ? 'Увійти' : 'Створити акаунт' }}
        </button>
      </form>
    </div>

    <p class="again">
      <button type="button" class="btn btn-ghost" @click="welcome.reset()">
        Спитати про акаунт ще раз
      </button>
      <span class="mono">Поверне вікно, яке ви бачили при першому відкритті.</span>
    </p>

    <p class="note">
      Дивитись можна й без акаунта — каталог відкритий. «Мій список» і «Продовжити дивитись»
      сьогодні живуть у цьому браузері: історії перегляду в API поки що немає, тож акаунт
      тримає впізнаваність — те, до чого ця історія привʼяжеться, коли зʼявиться, і те, чим
      вас упізнає приставка.
    </p>

    <p v-if="!account && token && !checked" class="mono checking">Перевіряємо сесію…</p>
  </div>
</template>

<style scoped>
.account {
  padding: clamp(28px, 4vw, 56px) var(--gutter) 0;
  max-width: 560px;
}

h1 {
  font-weight: 500;
  font-size: clamp(30px, 4.4vw, 56px);
  letter-spacing: -0.01em;
  margin-bottom: clamp(20px, 3vw, 32px);
}

.card {
  padding: clamp(20px, 3vw, 32px);
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
}

.tabs {
  display: flex;
  gap: 8px;
  margin-bottom: 24px;
}

.tab {
  cursor: pointer;
  padding: 8px 16px;
  border-radius: var(--radius);
  border: 1px solid transparent;
  background: transparent;
  font-family: var(--font-display);
  font-size: 15px;
  color: var(--neutral-500);
  transition:
    color 160ms ease,
    border-color 160ms ease,
    background 160ms ease;
}

.tab:hover {
  color: var(--text);
}

.tab.on {
  color: var(--text);
  border-color: var(--accent);
  background: var(--accent-veil);
}

form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

label {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.who {
  font-family: var(--font-display);
  font-size: 26px;
  margin: 8px 0 4px;
}

.explain {
  margin: 0 0 22px;
  font-size: 14px;
  line-height: 1.6;
  color: var(--neutral-400);
  text-wrap: pretty;
}

.explain em {
  font-style: normal;
  color: var(--accent-300);
}

.row {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.mail {
  font-size: 13px;
  color: var(--neutral-600);
  margin-bottom: 20px;
}

.bad {
  font-size: 13px;
  color: var(--accent-300);
  margin-top: 12px;
}

/* Outlined like everything else — the accent is a line here too, not a flood.
   What marks it out is that it is the only border in the app that is not the
   accent or a neutral. */
.danger {
  border-color: #d9738a;
}

.danger:hover {
  border-color: #d9738a;
  background: color-mix(in srgb, #d9738a 14%, transparent);
}

.hint {
  margin: 14px 0 0;
  font-size: 12px;
  line-height: 1.6;
  color: var(--neutral-600);
  max-width: 46ch;
}

.again {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  margin-top: 24px;
  font-size: 12px;
  color: var(--neutral-700);
}

.note {
  margin-top: 24px;
  font-size: 14px;
  line-height: 1.6;
  color: var(--neutral-600);
  max-width: 60ch;
}

.checking {
  font-size: 12px;
  color: var(--neutral-700);
}
</style>
