<script setup lang="ts">
/**
 * The installs themselves.
 *
 * Server-side paging, because the table this reads is the one that grows: the
 * client is never handed rows it is not about to draw. Sorting is deliberately
 * off — the API returns newest-seen first and offers no order to ask for, and a
 * sortable header that silently sorts one page of twenty-five is a lie.
 */
import { onMounted, ref, watch } from 'vue'

import { PLATFORMS } from '@/api/types'
import type { Platform } from '@/api/types'
import { useRecords } from '@/composables/useRecords'
import { count, moment, since } from '@/format'
import { mdiMagnify } from '@/icons'

const records = useRecords()

/** Bound to the box; the composable turns it into a request after a pause. */
const typed = ref('')
watch(typed, (term) => records.searchLater(term))

interface PlatformChoice {
  title: string
  value: Platform | null
}

const platforms: PlatformChoice[] = [
  { title: 'Усі платформи', value: null },
  ...PLATFORMS.map((name) => ({ title: name, value: name })),
]

const headers = [
  { title: 'Інсталяція', key: 'id', sortable: false },
  { title: 'Платформа', key: 'platform', sortable: false, width: 130 },
  { title: 'Версія', key: 'version', sortable: false, width: 120 },
  { title: 'Джерело', key: 'vendor', sortable: false },
  { title: "З'явилась", key: 'registered_at', sortable: false, width: 150 },
  { title: 'Востаннє бачена', key: 'last_seen_at', sortable: false, width: 170 },
]

onMounted(() => void records.load())

defineExpose({ reload: () => void records.load() })
</script>

<template>
  <v-card class="table">
    <div class="table__head">
      <h2 class="table__title">Інсталяції</h2>

      <div class="table__filters">
        <v-text-field
          v-model="typed"
          placeholder="uuid, версія або джерело"
          :prepend-inner-icon="mdiMagnify"
          clearable
          density="compact"
          class="table__search"
        />
        <v-select
          v-model="records.platform.value"
          :items="platforms"
          density="compact"
          class="table__platform"
        />
      </div>
    </div>

    <v-alert v-if="records.error.value" type="error" variant="tonal" class="table__error">
      {{ records.error.value }}
    </v-alert>

    <v-data-table-server
      v-model:page="records.page.value"
      v-model:items-per-page="records.perPage.value"
      :headers="headers"
      :items="records.items.value"
      :items-length="records.total.value"
      :loading="records.loading.value"
      :items-per-page-options="[10, 25, 50, 100]"
      density="comfortable"
      hover
    >
      <template #item.id="{ item }">
        <code class="table__uuid" :title="item.id">{{ item.id.slice(0, 8) }}</code>
      </template>

      <template #item.platform="{ item }">
        <v-chip size="small" variant="tonal" label>{{ item.platform }}</v-chip>
      </template>

      <template #item.version="{ item }">
        <span class="figures">{{ item.version }}</span>
      </template>

      <template #item.vendor="{ item }">
        <span v-if="item.vendor" class="table__vendor">{{ item.vendor }}</span>
        <span v-else class="table__none">—</span>
      </template>

      <template #item.registered_at="{ item }">
        <span :title="moment(item.registered_at)">{{ moment(item.registered_at) }}</span>
      </template>

      <template #item.last_seen_at="{ item }">
        <span :title="moment(item.last_seen_at)">{{ since(item.last_seen_at) }}</span>
      </template>

      <template #no-data>
        <div class="table__empty">
          {{ records.search.value || records.platform.value ? 'Нічого не знайшлось' : 'Ще порожньо' }}
        </div>
      </template>

      <template #footer.prepend>
        <span class="table__total">усього {{ count(records.total.value) }}</span>
      </template>
    </v-data-table-server>
  </v-card>
</template>

<style scoped lang="scss">
.table {
  &__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 20px;
    flex-wrap: wrap;
  }

  &__title {
    font-size: 1rem;
    font-weight: 600;
    margin: 0;
    color: var(--chart-ink);
  }

  &__filters {
    display: flex;
    gap: 12px;
    flex: 1 1 380px;
    justify-content: flex-end;

    @include stacked {
      flex-basis: 100%;
    }
  }

  &__search {
    max-width: 320px;
  }

  &__platform {
    max-width: 190px;
  }

  &__error {
    margin: 0 20px 12px;
  }

  &__uuid {
    @include figures;
    font-size: 0.8125rem;
    color: var(--chart-ink-soft);
  }

  &__vendor {
    font-size: 0.8125rem;
    color: var(--chart-ink-soft);
  }

  &__none {
    color: var(--chart-muted);
  }

  &__empty {
    padding: 32px 0;
    text-align: center;
    color: var(--chart-muted);
    font-size: 0.875rem;
  }

  &__total {
    color: var(--chart-muted);
    font-size: 0.8125rem;
    // The table renders its own "rows per page" immediately after this slot.
    margin-right: 16px;
    @include figures;
  }
}

.figures {
  @include figures;
}
</style>
