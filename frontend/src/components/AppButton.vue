<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(
  defineProps<{
    variant?: "primary" | "secondary" | "ghost" | "danger";
    type?: "button" | "submit";
    loading?: boolean;
    disabled?: boolean;
  }>(),
  { variant: "primary", type: "button", loading: false, disabled: false },
);

const variantClass = computed(() => {
  switch (props.variant) {
    case "secondary":
      return "bg-surface text-text border border-border-input hover:bg-bg";
    case "ghost":
      return "bg-transparent text-accent hover:bg-surface";
    case "danger":
      return "bg-danger text-white hover:opacity-90";
    default:
      return "bg-accent text-on-accent hover:opacity-90";
  }
});
</script>

<template>
  <button
    :type="type"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
    :class="[
      'inline-flex min-h-10 items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold transition',
      'disabled:cursor-not-allowed disabled:opacity-50',
      variantClass,
    ]"
  >
    <span
      v-if="loading"
      class="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
      aria-hidden="true"
    />
    <slot />
  </button>
</template>
