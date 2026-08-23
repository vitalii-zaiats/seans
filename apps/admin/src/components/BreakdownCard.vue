<script setup lang="ts">
/**
 * One dimension of the install base, as labelled bars.
 *
 * Bars rather than a donut: these are compared, and a reader cannot compare two
 * arcs that are not adjacent. One hue for every bar, because the category is
 * already named beside it — colouring each bar differently would burn the only
 * free channel on information the label already carries.
 *
 * Each bar is split in two: the part that has launched recently, and the rest.
 * That is the question worth asking of an install count — a version with two
 * thousand installs and nine active ones is a version nobody is running.
 */
import { computed } from 'vue'

import type { Slice } from '@/api/types'
import { count, share } from '@/format'

const props = defineProps<{
  title: string
  items: Slice[]
  /** Shown in place of a null name — see `Slice.name`. */
  fallback: string
  empty: string
  activeDays: number
}>()

/** Bars are scaled to the biggest row, not to the total: with a long tail every
 *  bar but the first would otherwise be a sliver. */
const widest = computed(() => props.items.reduce((top, item) => Math.max(top, item.installs), 0))

function width(value: number): string {
  return widest.value === 0 ? '0%' : `${(value / widest.value) * 100}%`
}

function label(item: Slice): string {
  return item.name ?? props.fallback
}

/**
 * The filled share of a bar, as a CSS width.
 *
 * Not `share()` — that formats for a reader, and this locale writes a decimal
 * with a comma. `width: 71,4%` is not a length, so the browser drops the
 * declaration and the bar silently renders empty.
 */
function portion(item: Slice): string {
  return item.installs === 0 ? '0%' : `${(item.active / item.installs) * 100}%`
}
</script>

<template>
  <v-card class="panel">
    <div class="panel__head">
      <h2 class="panel__title">{{ title }}</h2>
      <div class="panel__legend">
        <span class="panel__key"><i class="panel__swatch panel__swatch--active" />активні</span>
        <span class="panel__key"><i class="panel__swatch panel__swatch--rest" />решта</span>
      </div>
    </div>

    <p v-if="items.length === 0" class="panel__empty">{{ empty }}</p>

    <ul v-else class="panel__rows">
      <li v-for="item in items" :key="item.name ?? '∅'" class="row">
        <div class="row__head">
          <span class="row__name" :title="label(item)">{{ label(item) }}</span>
          <span class="row__count figures">{{ count(item.installs) }}</span>
        </div>

        <div
          class="row__bar"
          :style="{ width: width(item.installs) }"
          :title="`${count(item.active)} з ${count(item.installs)} запускались за останні ${activeDays} дн.`"
        >
          <span class="row__active" :style="{ width: portion(item) }" />
        </div>

        <div class="row__meta">
          {{ count(item.active) }} активних · {{ share(item.active, item.installs) }}
        </div>
      </li>
    </ul>
  </v-card>
</template>

<style scoped lang="scss">
.panel {
  padding: 20px;

  &__head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
    margin-bottom: 16px;
  }

  &__title {
    font-size: 1rem;
    font-weight: 600;
    margin: 0;
    color: var(--chart-ink);
  }

  &__legend {
    display: flex;
    gap: 12px;
  }

  &__key {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 0.75rem;
    color: var(--chart-muted);
  }

  &__swatch {
    width: 9px;
    height: 9px;
    border-radius: 2px;

    &--active {
      background: var(--series-1);
    }

    &--rest {
      background: var(--series-track);
    }
  }

  &__empty {
    margin: 0;
    color: var(--chart-muted);
    font-size: 0.875rem;
  }

  &__rows {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
}

.row {
  &__head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 5px;
  }

  &__name {
    // `android`, `0.1.2`, `com.android.shell` — every row here is a machine's
    // own word for itself, and none of them is prose. The mono face says so,
    // and keeps a version number from being read as a date.
    // A step down from the 0.875rem the row was set at: JetBrains Mono has a
    // taller x-height and wider letters than Karla, so the same nominal size
    // reads bigger and `com.android.shell` starts crowding its count.
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    color: var(--chart-ink);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  &__count {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--chart-ink);
    flex: none;
  }

  &__bar {
    height: 8px;
    border-radius: 4px;
    background: var(--series-track);
    // A 2px surface gap between the two segments, rather than a border drawn
    // around either of them.
    box-shadow: inset 0 0 0 0 transparent;
    min-width: 4px;
    overflow: hidden;
    display: flex;
  }

  &__active {
    background: var(--series-1);
    border-radius: 4px;
    box-shadow: 2px 0 0 0 var(--chart-surface);
  }

  &__meta {
    margin-top: 5px;
    font-size: 0.75rem;
    color: var(--chart-muted);
    @include figures;
  }
}

.figures {
  @include figures;
}
</style>
