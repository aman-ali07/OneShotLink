<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import { copyText } from "@/lib/clipboard";

const props = withDefaults(defineProps<{ text: string; label?: string }>(), {
  label: "Copy",
});

const state = ref<"idle" | "copied" | "failed">("idle");
let timer: ReturnType<typeof setTimeout> | undefined;

async function copy() {
  state.value = (await copyText(props.text)) ? "copied" : "failed";

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
      class="inline-flex min-h-11 items-center rounded-md border border-border-input bg-surface px-3 py-1.5 text-sm font-medium text-text hover:bg-bg"
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
