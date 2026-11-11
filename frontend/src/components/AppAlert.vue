<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(defineProps<{ tone?: "info" | "success" | "danger" }>(), {
  tone: "info",
});

const role = computed(() => (props.tone === "danger" ? "alert" : "status"));

const toneClass = computed(() => {
  switch (props.tone) {
    case "success":
      return "border-success/40 text-success";
    case "danger":
      return "border-danger/40 text-danger";
    default:
      return "border-border text-muted";
  }
});
</script>

<template>
  <div :role="role" :class="['rounded-md border bg-surface px-4 py-3 text-sm', toneClass]">
    <slot />
  </div>
</template>
