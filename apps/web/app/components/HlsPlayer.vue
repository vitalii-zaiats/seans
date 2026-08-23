<script setup lang="ts">
/**
 * The video, and the least chrome that can carry it.
 *
 * Safari plays HLS itself; everywhere else hls.js does, and it is imported only
 * when a stream is actually attached — there is no reason to ship 400 kB to
 * somebody who is only reading a synopsis.
 *
 * The quality ladder is read off the manifest rather than invented: a stream
 * with one rung gets no menu at all, and neither does Safari, which plays HLS
 * natively and offers no way to pick a variant. A control that does nothing is
 * worse than no control.
 */

import type Hls from 'hls.js'

const props = withDefaults(
  defineProps<{
    /** The playlist to attach. Null while there is nothing yet. */
    src: string | null
    poster?: string | null
    /** Seconds to open at, from wherever this was left. */
    start?: number
  }>(),
  { poster: null, start: 0 },
)

const emit = defineEmits<{
  /** Where the playhead is. A bookmark, not telemetry — throttled. */
  progress: [{ position: number; duration: number }]
  ended: []
  /** The browser refused to start on its own. Somebody has to press play. */
  blocked: []
}>()

/**
 * A resume point in the closing seconds is worse than none: it drops somebody
 * at the credits of a film they finished.
 */
const TAIL = 20

/** How often a position is worth writing down. Ten seconds of lost place is nothing. */
const EVERY = 10

const video = ref<HTMLVideoElement | null>(null)
const problem = ref<string | null>(null)
let engine: Hls | null = null
let reported = 0

interface Rung {
  index: number
  label: string
}

const rungs = ref<Rung[]>([])
const native = ref(false)
/** -1 is auto, which is also hls.js's word for it. */
const chosen = ref(-1)
/** What auto settled on, so "Авто" can say what it is actually doing. */
const running = ref<string | null>(null)

function label(level: { height?: number; bitrate?: number }): string {
  if (level.height) return `${level.height}p`
  return level.bitrate ? `${Math.round(level.bitrate / 1000)}k` : 'потік'
}

function choose(index: number): void {
  chosen.value = index
  // `currentLevel` switches now rather than at the next segment: somebody who
  // just asked for 1080p wants to see it, not agree to it for later.
  if (engine) engine.currentLevel = index
}

function lengthOf(element: HTMLVideoElement): number {
  return Number.isFinite(element.duration) && element.duration > 0 ? element.duration : 0
}

function opened(): void {
  const element = video.value
  if (!element) return
  const total = lengthOf(element)
  if (props.start > 0 && (total === 0 || props.start < total - TAIL)) {
    element.currentTime = props.start
  }
}

function ticked(): void {
  const element = video.value
  if (!element || element.seeking) return
  if (Math.abs(element.currentTime - reported) < EVERY) return
  reported = element.currentTime
  emit('progress', { position: element.currentTime, duration: lengthOf(element) })
}

/** On pause and on leaving: the two moments a place is most worth keeping. */
function paused(): void {
  const element = video.value
  if (!element) return
  reported = element.currentTime
  emit('progress', { position: element.currentTime, duration: lengthOf(element) })
}

function detach(): void {
  engine?.destroy()
  engine = null
  rungs.value = []
  chosen.value = -1
  running.value = null
}

async function attach(src: string): Promise<void> {
  detach()
  problem.value = null

  const element = video.value
  if (!element) return

  const { default: HlsEngine } = await import('hls.js')

  // hls.js first, native second — and not the other way round, which is how
  // this is usually written and is wrong here.
  //
  // Chrome answers `canPlayType('application/vnd.apple.mpegurl')` with
  // `"maybe"`, which is truthy and is a polite shrug: it cannot demux a
  // playlist. Handing it the `.m3u8` as a `src` therefore *looks* like it
  // works — something plays — while hls.js never runs, so there is no manifest
  // to read a quality ladder off and no way to switch a level. Preferring the
  // engine wherever it is supported gives one code path, and Safari (which
  // supports MSE too) gets the ladder as well.
  if (!HlsEngine.isSupported()) {
    native.value = element.canPlayType('application/vnd.apple.mpegurl') !== ''
    if (!native.value) {
      problem.value = 'Цей браузер не вміє HLS'
      return
    }
    element.src = src
    await start(element)
    return
  }

  engine = new HlsEngine({ enableWorker: true })

  engine.on(HlsEngine.Events.MANIFEST_PARSED, () => {
    rungs.value = (engine?.levels ?? [])
      .map((level, index) => ({ index, label: label(level), height: level.height ?? 0 }))
      // Best first: the order a quality menu is read in.
      .sort((a, b) => b.height - a.height)
      .map(({ index, label: text }) => ({ index, label: text }))
    chosen.value = engine?.currentLevel ?? -1
  })

  engine.on(HlsEngine.Events.LEVEL_SWITCHED, (_event, data) => {
    const level = engine?.levels?.[data.level]
    running.value = level ? label(level) : null
  })

  engine.on(HlsEngine.Events.ERROR, (_event, data) => {
    // Only fatal ones are worth saying: hls.js recovers from the rest by
    // itself, and reporting those would make the screen flicker with problems
    // that already fixed themselves.
    if (data.fatal) problem.value = `${data.type}: ${data.details}`
  })

  engine.loadSource(src)
  engine.attachMedia(element)
  await start(element)
}

/** Attached, therefore playable — the only moment autoplay can mean anything. */
async function start(element: HTMLVideoElement): Promise<void> {
  try {
    await element.play()
  } catch {
    // Some browsers want a gesture in this document first. Say so; do not sulk.
    emit('blocked')
  }
}

defineExpose({
  toggle(): void {
    const element = video.value
    if (!element) return
    if (element.paused) void element.play().catch(() => emit('blocked'))
    else element.pause()
  },
  skip(delta: number): void {
    const element = video.value
    if (element) element.currentTime = Math.max(0, element.currentTime + delta)
  },
  /** Where the playhead is, for whoever is about to close this. */
  where(): { position: number; duration: number } {
    const element = video.value
    if (!element) return { position: 0, duration: 0 }
    return { position: element.currentTime, duration: lengthOf(element) }
  },
})

// Not `immediate`: an immediate watcher runs during setup, before the template
// exists, so the ref is still null and the attach quietly does nothing — which
// is how a player ends up showing controls over silence. The first attach
// belongs on mount.
watch(
  () => props.src,
  (next) => {
    if (!next) {
      detach()
      return
    }
    reported = 0
    void attach(next)
  },
  { flush: 'post' },
)

onMounted(() => {
  if (props.src) void attach(props.src)
  // Walking away is the commonest way to stop watching, and it fires no `pause`.
  window.addEventListener('pagehide', paused)
})

onBeforeUnmount(() => {
  window.removeEventListener('pagehide', paused)
  paused()
  detach()
})
</script>

<template>
  <div class="hls">
    <video
      ref="video"
      controls
      playsinline
      :poster="poster ?? undefined"
      @loadedmetadata="opened"
      @timeupdate="ticked"
      @pause="paused"
      @ended="emit('ended')"
    />

    <!-- Under the video, never over it: the native controls own that strip, and
         two rows of chrome fighting for one corner is how a player gets ugly. -->
    <div v-if="rungs.length > 1" class="bar">
      <label class="sr-only" for="quality">Якість</label>
      <select
        id="quality"
        class="quality mono"
        :value="chosen"
        @change="choose(Number(($event.target as HTMLSelectElement).value))"
      >
        <option :value="-1">Авто{{ running ? ` · ${running}` : '' }}</option>
        <option v-for="rung in rungs" :key="rung.index" :value="rung.index">
          {{ rung.label }}
        </option>
      </select>
    </div>

    <p v-if="problem" class="problem mono">{{ problem }}</p>
  </div>
</template>

<style scoped>
.hls {
  display: flex;
  flex-direction: column;
  min-height: 0;
}

video {
  display: block;
  width: 100%;
  min-height: 0;
  flex: 1;
  background: #000;
}

.bar {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 8px var(--gutter);
}

.quality {
  padding: 4px 10px;
  border-radius: var(--radius);
  border: 1px solid var(--neutral-800);
  background: var(--surface);
  color: var(--neutral-300);
  font-size: 12px;
}

.quality:hover {
  border-color: var(--neutral-600);
}

.problem {
  margin: 0;
  padding: 10px var(--gutter);
  font-size: 12px;
  color: var(--accent-300);
}
</style>
