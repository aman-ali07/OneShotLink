<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import { accountsEnabled } from "@/lib/authMode";

const route = useRoute();
// Hidden until /config proves accounts are on. Defaulting to visible flashed a
// dead-end Account link on instances with AUTH_MODE=disabled.
const showAccount = ref(false);

onMounted(async () => {
  showAccount.value = await accountsEnabled();
});

const links = [
  { to: "/", label: "New secret" },
  { to: "/dashboard", label: "Account" },
];
const visibleLinks = () => links.filter((link) => link.to !== "/dashboard" || showAccount.value);

// Highlight the section, not just an exact path, so recipients and responders
// can see where they are on /secret/:key, /request/:key and the auth screens.
const isActive = (to: string) => {
  if (to === "/") return route.path === "/";
  if (to === "/dashboard") {
    return ["/dashboard", "/signin", "/signup"].includes(route.path);
  }
  return route.path.startsWith(to);
};
</script>

<template>
  <header class="border-b border-border bg-surface">
    <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
      <RouterLink to="/" class="group flex items-center gap-3" aria-label="OneShotLink home">
        <span
          class="flex items-center justify-center rounded-md bg-surface"
          :style="{ width: 'var(--ots-mark-size)', height: 'var(--ots-mark-size)' }"
          aria-hidden="true"
        >
          <!-- The same single-stroke chain as site/favicon.svg: whole until read,
               then broken at the seam. One colour, no fill, legible at 16px. -->
          <svg viewBox="0 0 32 32" class="h-7 w-7" fill="none" stroke="var(--ots-accent)" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round">
            <path d="M14 9h-1a7 7 0 0 0-7 7 7 7 0 0 0 7 7h1" />
            <path d="M18 9h1a7 7 0 0 1 7 7 7 7 0 0 1-7 7h-1" />
          </svg>
        </span>
        <span class="text-base font-semibold tracking-tight text-text">OneShotLink</span>
      </RouterLink>

      <nav aria-label="Primary" class="flex items-center gap-1 sm:gap-2">
        <RouterLink
          v-for="link in visibleLinks()"
          :key="link.to"
          :to="link.to"
          :aria-current="isActive(link.to) ? 'page' : undefined"
          :class="[
            'min-h-11 items-center rounded-md px-3 text-sm font-medium transition-colors',
            // The logo already goes home; drop the duplicate link on the
            // narrowest screens so the header cannot overflow at 320px.
            link.to === '/' ? 'hidden sm:inline-flex' : 'inline-flex',
            isActive(link.to)
              ? 'bg-accent/10 text-accent'
              : 'text-muted hover:bg-bg hover:text-text',
          ]"
        >
          {{ link.label }}
        </RouterLink>
        <RouterLink
          v-if="route.path !== '/'"
          to="/"
          class="ml-1 hidden min-h-11 items-center rounded-md bg-accent px-3 text-sm font-semibold text-on-accent transition-colors hover:bg-accent-hover sm:inline-flex"
        >
          Create link
        </RouterLink>
      </nav>
    </div>
  </header>
</template>
