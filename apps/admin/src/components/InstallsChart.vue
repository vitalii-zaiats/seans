<script setup lang="ts">
/**
 * New installs and last-seen installs, by day.
 *
 * Drawn by hand in SVG rather than pulled from a chart library: two lines, a
 * grid and a crosshair is a morning's work, and a library would arrive with its
 * own colours, its own idea of a tooltip, and its own theme to keep in step
 * with Vuetify's.
 *
 * Both series are counts of installs, so they share one axis. A second scale on
 * the right would let the two lines cross wherever the scales happened to put
 * them, which is a correlation the data does not contain.
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

import type { Day } from '@/api/types'
import { count, dayLong, dayShort } from '@/format'
import { mdiChartLine, mdiTable } from '@/icons'

const props = defineProps<{ days: Day[]; activeDays: number; loading?: boolean }>()

const HEIGHT = 288
const PAD = { top: 16, right: 20, bottom: 32, left: 52 }

const frame = ref<HTMLElement | null>(null)
const width = ref(720)
const hovered = ref<number | null>(null)
const asTable = ref(false)

let observer: ResizeObserver | undefined

onMounted(() => {
  const element = frame.value
  if (!element) return
  observer = new ResizeObserver(([entry]) => {
    // Never zero: a zero-width scale divides by zero and paints `NaN` into
    // every coordinate, which SVG renders as nothing at all.
    if (entry) width.value = Math.max(320, entry.contentRect.width)
  })
  observer.observe(element)
})

onBeforeUnmount(() => observer?.disconnect())

const plot = computed(() => ({
  width: Math.max(1, width.value - PAD.left - PAD.right),
  height: HEIGHT - PAD.top - PAD.bottom,
}))

const empty = computed(() => props.days.every((day) => day.created === 0 && day.seen === 0))

/** A round top and ticks that land on whole installs — a half-install is not a thing. */
const scale = computed(() => {
  const highest = props.days.reduce((top, day) => Math.max(top, day.created, day.seen), 0)

  let best: { top: number; ticks: number[] } | null = null
  for (const divisions of [5, 4]) {
    const step = Math.max(1, niceStep(Math.max(highest, 1) / divisions))
    const top = step * divisions
    if (top < Math.max(highest, 1)) continue
    if (best === null || top < best.top) {
      best = { top, ticks: Array.from({ length: divisions + 1 }, (_, index) => index * step) }
    }
  }
  return best ?? { top: 5, ticks: [0, 1, 2, 3, 4, 5] }
})

function niceStep(rough: number): number {
  const magnitude = 10 ** Math.floor(Math.log10(rough))
  const normalised = rough / magnitude
  const step = normalised <= 1 ? 1 : normalised <= 2 ? 2 : normalised <= 5 ? 5 : 10
  return step * magnitude
}

function x(index: number): number {
  const last = props.days.length - 1
  if (last <= 0) return PAD.left + plot.value.width / 2
  return PAD.left + (index / last) * plot.value.width
}

function y(value: number): number {
  return PAD.top + plot.value.height * (1 - value / scale.value.top)
}

function path(pick: (day: Day) => number): string {
  return props.days.map((day, index) => `${index === 0 ? 'M' : 'L'}${x(index)} ${y(pick(day))}`).join(' ')
}

const createdPath = computed(() => path((day) => day.created))
const seenPath = computed(() => path((day) => day.seen))

/** At most six, always including the ends — more than that and they collide. */
const xLabels = computed(() => {
  const last = props.days.length - 1
  if (last < 0) return []
  const wanted = Math.min(6, Math.max(2, Math.floor(plot.value.width / 90)))
  const stride = Math.max(1, Math.round(last / (wanted - 1)))

  const marks: { index: number; label: string }[] = []
  for (let index = 0; index <= last; index += stride) {
    const day = props.days[index]
    if (day) marks.push({ index, label: dayShort(day.day) })
  }
  const tail = props.days[last]
  const previous = marks[marks.length - 1]
  if (tail && previous && previous.index !== last) {
    // The right-hand end is the one a reader looks for. If the stride missed
    // it, drop whatever landed too close to make room.
    if (x(last) - x(previous.index) < 56) marks.pop()
    marks.push({ index: last, label: dayShort(tail.day) })
  }
  return marks
})

/**
 * The endpoint labels, but only when they will not sit on top of each other.
 * Labelling the last point of each line saves the reader a trip to the legend;
 * two labels 3px apart costs them one.
 */
const endLabels = computed(() => {
  const last = props.days[props.days.length - 1]
  if (!last || empty.value) return null
  const gap = Math.abs(y(last.created) - y(last.seen))
  return gap >= 15 ? last : null
})

function nearest(event: PointerEvent): void {
  const element = frame.value
  if (!element || props.days.length === 0) return
  const bounds = element.getBoundingClientRect()
  const offset = event.clientX - bounds.left - PAD.left
  const last = props.days.length - 1
  const index = last <= 0 ? 0 : Math.round((offset / plot.value.width) * last)
  hovered.value = Math.min(last, Math.max(0, index))
}

const tip = computed(() => {
  const index = hovered.value
  if (index === null) return null
  const day = props.days[index]
  if (!day) return null

  // Flip to the left of the crosshair near the right edge, so the box never
  // hangs off the card.
  const at = x(index)
  const flip = at > PAD.left + plot.value.width - 150
  return { day, at, flip }
})
</script>

<template>
  <v-card class="chart">
    <div class="chart__head">
      <div>
        <h2 class="chart__title">Встановлення по днях</h2>
        <p class="chart__note">
          Дні за UTC. «Востаннє бачені» — це інсталяції, чий останній запуск припав на цей день,
          тому вчорашній стовпчик спадає, коли вони повертаються.
        </p>
      </div>

      <v-btn
        :icon="asTable ? mdiChartLine : mdiTable"
        :aria-label="asTable ? 'Показати графік' : 'Показати таблицю'"
        size="small"
        density="comfortable"
        @click="asTable = !asTable"
      />
    </div>

    <div class="chart__legend">
      <span class="chart__key"><i class="chart__swatch chart__swatch--1" />Нові</span>
      <span class="chart__key"><i class="chart__swatch chart__swatch--2" />Востаннє бачені</span>
    </div>

    <v-table v-if="asTable" density="compact" class="chart__table">
      <thead>
        <tr>
          <th>День</th>
          <th class="text-right">Нові</th>
          <th class="text-right">Востаннє бачені</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="day in days" :key="day.day">
          <td>{{ dayLong(day.day) }}</td>
          <td class="text-right figures">{{ count(day.created) }}</td>
          <td class="text-right figures">{{ count(day.seen) }}</td>
        </tr>
      </tbody>
    </v-table>

    <div v-else ref="frame" class="chart__frame" @pointerleave="hovered = null">
      <svg
        :width="width"
        :height="HEIGHT"
        role="img"
        :aria-label="`Нові та востаннє бачені інсталяції за ${days.length} днів`"
        @pointermove="nearest"
      >
        <g>
          <line
            v-for="tick in scale.ticks"
            :key="`grid-${tick}`"
            :x1="PAD.left"
            :x2="width - PAD.right"
            :y1="y(tick)"
            :y2="y(tick)"
            :class="tick === 0 ? 'chart__axis' : 'chart__grid'"
          />
          <text
            v-for="tick in scale.ticks"
            :key="`tick-${tick}`"
            :x="PAD.left - 10"
            :y="y(tick) + 4"
            text-anchor="end"
            class="chart__tick"
          >
            {{ count(tick) }}
          </text>
        </g>

        <g>
          <text
            v-for="mark in xLabels"
            :key="`x-${mark.index}`"
            :x="x(mark.index)"
            :y="HEIGHT - 10"
            text-anchor="middle"
            class="chart__tick"
          >
            {{ mark.label }}
          </text>
        </g>

        <template v-if="!empty">
          <path :d="seenPath" class="chart__line chart__line--2" />
          <path :d="createdPath" class="chart__line chart__line--1" />
        </template>

        <template v-if="endLabels">
          <text
            :x="x(days.length - 1) - 8"
            :y="y(endLabels.created) - 8"
            text-anchor="end"
            class="chart__endpoint"
          >
            {{ count(endLabels.created) }}
          </text>
          <text
            :x="x(days.length - 1) - 8"
            :y="y(endLabels.seen) - 8"
            text-anchor="end"
            class="chart__endpoint"
          >
            {{ count(endLabels.seen) }}
          </text>
        </template>

        <g v-if="tip">
          <line
            :x1="tip.at"
            :x2="tip.at"
            :y1="PAD.top"
            :y2="PAD.top + plot.height"
            class="chart__crosshair"
          />
          <!-- A ring in the surface colour, not a stroke: where the two dots
               overlap, this is what keeps them two dots. -->
          <circle :cx="tip.at" :cy="y(tip.day.seen)" r="5" class="chart__dot chart__dot--2" />
          <circle :cx="tip.at" :cy="y(tip.day.created)" r="5" class="chart__dot chart__dot--1" />
        </g>
      </svg>

      <div v-if="empty && !loading" class="chart__empty">Жодної інсталяції за цей період</div>

      <div
        v-if="tip"
        class="chart__tip"
        :class="{ 'chart__tip--flip': tip.flip }"
        :style="{ left: `${tip.at}px` }"
      >
        <div class="chart__tip-day">{{ dayLong(tip.day.day) }}</div>
        <div class="chart__tip-row">
          <i class="chart__swatch chart__swatch--1" />
          <span>Нові</span>
          <b class="figures">{{ count(tip.day.created) }}</b>
        </div>
        <div class="chart__tip-row">
          <i class="chart__swatch chart__swatch--2" />
          <span>Востаннє бачені</span>
          <b class="figures">{{ count(tip.day.seen) }}</b>
        </div>
      </div>
    </div>

    <v-progress-linear v-if="loading" indeterminate height="2" class="chart__loading" />
  </v-card>
</template>

<style scoped lang="scss">
.chart {
  padding: 20px;
  position: relative;

  &__head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
  }

  &__title {
    font-size: 1rem;
    font-weight: 600;
    margin: 0;
    color: var(--chart-ink);
  }

  &__note {
    margin: 4px 0 0;
    font-size: 0.8125rem;
    color: var(--chart-muted);
    max-width: 62ch;
  }

  &__legend {
    display: flex;
    gap: 18px;
    margin: 14px 0 6px;
  }

  &__key {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    font-size: 0.8125rem;
    // Text ink, never the series colour — the swatch carries the identity.
    color: var(--chart-ink-soft);
  }

  &__swatch {
    width: 10px;
    height: 10px;
    border-radius: 3px;
    flex: none;

    &--1 {
      background: var(--series-1);
    }

    &--2 {
      background: var(--series-2);
    }
  }

  &__frame {
    position: relative;
    overflow: hidden;
    touch-action: pan-y;
  }

  svg {
    display: block;
  }

  &__grid {
    stroke: var(--chart-grid);
    stroke-width: 1;
  }

  &__axis {
    stroke: var(--chart-axis);
    stroke-width: 1;
  }

  &__tick {
    fill: var(--chart-muted);
    font-size: 11px;
    @include figures;
  }

  &__line {
    fill: none;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;

    &--1 {
      stroke: var(--series-1);
    }

    &--2 {
      stroke: var(--series-2);
    }
  }

  &__endpoint {
    fill: var(--chart-ink-soft);
    font-size: 11px;
    font-weight: 600;
    @include figures;
  }

  &__crosshair {
    stroke: var(--chart-axis);
    stroke-width: 1;
  }

  &__dot {
    stroke: var(--chart-surface);
    stroke-width: 2;

    &--1 {
      fill: var(--series-1);
    }

    &--2 {
      fill: var(--series-2);
    }
  }

  &__empty {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    color: var(--chart-muted);
    font-size: 0.875rem;
    pointer-events: none;
  }

  &__tip {
    position: absolute;
    top: 12px;
    transform: translateX(12px);
    min-width: 190px;
    padding: 10px 12px;
    border-radius: 8px;
    background: rgb(var(--v-theme-surface));
    border: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
    box-shadow: 0 6px 20px rgb(0 0 0 / 12%);
    pointer-events: none;
    font-size: 0.8125rem;

    &--flip {
      transform: translateX(calc(-100% - 12px));
    }
  }

  &__tip-day {
    font-weight: 600;
    margin-bottom: 6px;
    color: var(--chart-ink);
  }

  &__tip-row {
    display: grid;
    grid-template-columns: 10px 1fr auto;
    align-items: center;
    gap: 8px;
    color: var(--chart-ink-soft);
    line-height: 1.7;
  }

  &__table {
    max-height: 288px;
    overflow-y: auto;
  }

  &__loading {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
  }
}

.figures {
  @include figures;
}
</style>
