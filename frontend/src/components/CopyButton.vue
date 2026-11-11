<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";

const props = withDefaults(defineProps<{ text: string; label?: string }>(), {
  label: "Copy",
});

const state = ref<"idle" | "copied" | "failed">("idle");
let timer: ReturnType<typeof setTimeout> | undefined;

function fallbackCopy(value: string): boolean {
  const area = document.createElement("textarea");
  area.value = value;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  const ok = document.execCommand("copy");
  document.body.removeChild(area);
  return ok;
}

async function copy() {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(props.text);
    } else if (!fallbackCopy(props.text)) {
      throw new Error("copy failed");
    }
    state.value = "copied";
  } catch {
    state.value = "failed";
  }

  if (timer) clearTimeout(timer);
  timer = setTimeout(() => {
    state.value = "idle";
  }, 2500);
}

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer);
});
</script>

<template>
  <div class="flex items-center gap-2">
    <button
      type="button"
      class="inline-flex min-h-9 items-center rounded-md border border-border-input bg-surface px-3 py-1.5 text-sm font-medium text-text hover:bg-bg"
      @click="copy"
    >
      {{ state === "copied" ? "Copied" : label }}
    </button>
    <span role="status" class="text-xs text-muted">
      <template v-if="state === 'copied'">Copied to clipboard.</template>
      <template v-else-if="state === 'failed'">Copy failed. Select the text and copy manually.</template>
    </span>
  </div>
</template>
