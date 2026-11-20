<script setup lang="ts">
import { useRoute } from "vue-router";

const route = useRoute();

const links = [
  { to: "/", label: "New secret" },
  { to: "/dashboard", label: "Account" },
];

const isActive = (to: string) => route.path === to;
</script>

<template>
  <header class="border-b border-border bg-surface/85 backdrop-blur-sm">
    <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
      <RouterLink to="/" class="group flex items-center gap-3" aria-label="OneShotLink home">
        <span
          class="flex h-9 w-9 items-center justify-center rounded-md bg-accent text-on-accent shadow-card"
          aria-hidden="true"
        >
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 2.5 4.5 5.8v5.4c0 4.6 3 8.4 7.5 10.3 4.5-1.9 7.5-5.7 7.5-10.3V5.8L12 2.5Z" />
            <path d="M9.2 11.3h5.6" stroke-linecap="round" />
          </svg>
        </span>
        <span class="text-base font-semibold tracking-tight text-text">OneShotLink</span>
      </RouterLink>

      <nav aria-label="Primary" class="flex items-center gap-1 sm:gap-2">
        <RouterLink
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          :aria-current="isActive(link.to) ? 'page' : undefined"
          :class="[
            'rounded-md px-3 py-2 text-sm font-medium transition-colors',
            isActive(link.to)
              ? 'bg-accent/10 text-accent'
              : 'text-muted hover:bg-bg hover:text-text',
          ]"
        >
          {{ link.label }}
        </RouterLink>
        <RouterLink
          to="/"
          class="ml-1 hidden rounded-md bg-accent px-3 py-2 text-sm font-semibold text-on-accent shadow-card transition-transform hover:-translate-y-px sm:inline-block"
        >
          Create link
        </RouterLink>
      </nav>
    </div>
  </header>
</template>
