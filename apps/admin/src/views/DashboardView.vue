<script setup lang="ts">
/**
 * The screen itself: four numbers, a chart, three breakdowns, and the table.
 *
 * The order is the order the questions get asked — how many are there, is that
 * going up, what are they running, and then finally which ones exactly.
 */
import { computed, onMounted, ref } from 'vue'

import BreakdownCard from '@/components/BreakdownCard.vue'
import InstallsChart from '@/components/InstallsChart.vue'
import InstallsTable from '@/components/InstallsTable.vue'
import StatTile from '@/components/StatTile.vue'
import { RANGES, useOverview } from '@/composables/useOverview'
import { moment, share } from '@/format'
import { mdiRefresh } from '@/icons'

const overview = useOverview()
const table = ref<InstanceType<typeof InstallsTable> | null>(null)

const data = computed(() => overview.overview.value)
const days = computed(() => data.value?.daily ?? [])

/**
 * Not a `Trend`: the share of installs that are alive has no honest previous
 * value here — the API compares counts across windows, and a ratio of two of
 * those is not the ratio it would have measured. So the tile carries a hint
 * instead of a delta.
 */
const alive = computed(() => {
  const found = data.value
  return found === null ? '—' : share(found.active.value, found.total)
})

function refresh(): void {
  void overview.load()
  table.value?.reload()
}

onMounted(() => void overview.load())
</script>

<template>
  <div class="board">
    <header class="board__bar">
      <div>
        <h1 class="board__title">Встановлення</h1>
        <p v-if="data" class="board__stamp">оновлено {{ moment(data.generated_at) }}</p>
      </div>

      <div class="board__controls">
        <!-- `selected-class` rather than `color`: the group's colour paints the
             selected button's background *and* its label the same primary, so
             the chosen range comes out as an unreadable blue-on-blue slab. The
             class below picks the paired `on-primary` ink instead. -->
        <v-btn-toggle
          v-model="overview.days.value"
          mandatory
          density="comfortable"
          selected-class="range--on"
          divided
          border
        >
          <v-btn
            v-for="range in RANGES"
            :key="range.days"
            :value="range.days"
            variant="text"
            size="small"
          >
            {{ range.label }}
          </v-btn>
        </v-btn-toggle>

        <v-btn
          :icon="mdiRefresh"
          aria-label="Оновити"
          :loading="overview.loading.value"
          @click="refresh"
        />
      </div>
    </header>

    <v-alert
      v-if="overview.error.value"
      type="error"
      variant="tonal"
      class="board__error"
      closable
      @click:close="overview.error.value = null"
    >
      {{ overview.error.value }}
    </v-alert>

    <section class="board__tiles">
      <StatTile
        label="Усього інсталяцій"
        :value="data?.total ?? 0"
        hint="за весь час, поза межами періоду"
        :loading="overview.loading.value"
      />
      <StatTile
        label="Нові"
        :value="data?.created.value ?? 0"
        :trend="data?.created ?? null"
        :loading="overview.loading.value"
      />
      <StatTile
        :label="`Активні за ${overview.activeDays.value} дн.`"
        :value="data?.active.value ?? 0"
        :trend="data?.active ?? null"
        :loading="overview.loading.value"
      />
      <v-card class="board__ratio">
        <div class="board__ratio-label">Частка живих</div>
        <div class="board__ratio-value">{{ alive }}</div>
        <div class="board__ratio-hint">активні від усіх інсталяцій</div>
      </v-card>
    </section>

    <InstallsChart
      :days="days"
      :active-days="overview.activeDays.value"
      :loading="overview.loading.value"
    />

    <section class="board__panels">
      <BreakdownCard
        title="Платформи"
        :items="data?.platforms ?? []"
        :active-days="overview.activeDays.value"
        fallback="невідомо"
        empty="Ще жодної інсталяції"
      />
      <BreakdownCard
        title="Версії"
        :items="data?.versions ?? []"
        :active-days="overview.activeDays.value"
        fallback="невідомо"
        empty="Ще жодної інсталяції"
      />
      <BreakdownCard
        title="Джерела"
        :items="data?.vendors ?? []"
        :active-days="overview.activeDays.value"
        fallback="не android"
        empty="Ще жодної інсталяції"
      />
    </section>

    <InstallsTable ref="table" />
  </div>
</template>

<style scoped lang="scss">
.board {
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 24px;
  max-width: 1440px;
  margin: 0 auto;

  @include narrow {
    padding: 16px;
    gap: 16px;
  }

  &__bar {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
  }

  &__title {
    margin: 0;
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--chart-ink);
  }

  &__stamp {
    margin: 2px 0 0;
    font-size: 0.8125rem;
    color: var(--chart-muted);
  }

  &__controls {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  :deep(.range--on) {
    background: rgb(var(--v-theme-primary));
    // Vuetify computes this to contrast with `primary` in whichever theme is
    // live, so the label stays legible when the palette changes.
    color: rgb(var(--v-theme-on-primary));

    // The active state paints an overlay in `currentColor`, which is now the
    // label's own ink — so without this the button is a solid block of the very
    // colour the text is written in.
    .v-btn__overlay {
      opacity: 0;
    }
  }

  &__error {
    margin: 0;
  }

  &__tiles {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;

    @include stacked {
      grid-template-columns: repeat(2, 1fr);
    }

    @include narrow {
      grid-template-columns: 1fr;
    }
  }

  &__panels {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 16px;

    @include stacked {
      grid-template-columns: 1fr;
    }
  }

  &__ratio {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-height: 132px;
  }

  &__ratio-label {
    font-size: 0.8125rem;
    font-weight: 500;
    letter-spacing: 0.02em;
    color: var(--chart-ink-soft);
  }

  &__ratio-value {
    font-size: 2.25rem;
    font-weight: 600;
    line-height: 1.1;
    color: var(--chart-ink);

    @include narrow {
      font-size: 1.875rem;
    }
  }

  &__ratio-hint {
    font-size: 0.8125rem;
    color: var(--chart-muted);
  }
}
</style>
