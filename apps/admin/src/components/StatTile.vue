<script setup lang="ts">
/**
 * One number, big, with the move that got it there.
 *
 * The delta carries an arrow and the words "проти попередніх N днів" as well as
 * a colour, because colour alone is not a channel every reader has.
 */
import { computed } from 'vue'

import type { Trend } from '@/api/types'
import { count, delta } from '@/format'
import { mdiArrowBottomRight, mdiArrowTopRight, mdiMinus } from '@/icons'

const props = defineProps<{
  label: string
  value: number
  /** A line under the number saying what it counts. */
  hint?: string
  trend?: Trend | null
  /** Set when a rise is the bad news — nothing on this screen is, yet. */
  inverted?: boolean
  loading?: boolean
}>()

type Direction = 'up' | 'down' | 'flat'

const direction = computed<Direction>(() => {
  const change = props.trend?.change
  if (change === undefined || change === null || change === 0) return 'flat'
  return change > 0 ? 'up' : 'down'
})

const icon = computed(() =>
  direction.value === 'up'
    ? mdiArrowTopRight
    : direction.value === 'down'
      ? mdiArrowBottomRight
      : mdiMinus,
)

const tone = computed(() => {
  if (direction.value === 'flat') return 'flat'
  const rising = direction.value === 'up'
  return rising !== Boolean(props.inverted) ? 'good' : 'bad'
})
</script>

<template>
  <v-card class="tile" :aria-busy="loading">
    <div class="tile__label">{{ label }}</div>

    <div class="tile__value">{{ count(value) }}</div>

    <div v-if="trend" class="tile__delta" :class="`is-${tone}`">
      <v-icon :icon="icon" size="16" />
      <span class="tile__change">{{ delta(trend.change) }}</span>
      <span class="tile__against">
        {{
          trend.change === null
            ? 'без попереднього періоду'
            : `проти ${count(trend.previous)} раніше`
        }}
      </span>
    </div>

    <div v-else-if="hint" class="tile__hint">{{ hint }}</div>
  </v-card>
</template>

<style scoped lang="scss">
.tile {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-height: 132px;

  &__label {
    font-size: 0.8125rem;
    font-weight: 500;
    letter-spacing: 0.02em;
    color: var(--chart-ink-soft);
  }

  &__value {
    // Proportional figures: a headline number is read, not compared down a
    // column. Tabular is for the table.
    font-family: var(--font-display);
    font-size: 2.25rem;
    font-weight: 600;
    line-height: 1.1;
    color: var(--chart-ink);

    @include narrow {
      font-size: 1.875rem;
    }
  }

  &__delta {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
    font-size: 0.8125rem;

    &.is-good {
      color: var(--delta-up);
    }

    &.is-bad {
      color: var(--delta-down);
    }

    &.is-flat {
      color: var(--chart-muted);
    }
  }

  &__change {
    font-weight: 600;
    @include figures;
  }

  &__against,
  &__hint {
    // The comparison is context, not the reading — it stays in text ink so the
    // coloured half is only ever the number itself.
    color: var(--chart-muted);
    font-size: 0.8125rem;
  }
}
</style>
