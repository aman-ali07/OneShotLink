<script setup lang="ts">
import AppFooter from "@/components/AppFooter.vue";
import AppHeader from "@/components/AppHeader.vue";

// With hash routing, a literal href="#main" is swallowed by the router. Focus
// the landmark directly and keep the URL unchanged.
function skipToMain(event: Event) {
  event.preventDefault();
  document.getElementById("main")?.focus();
}
</script>

<template>
  <div class="ots-ground flex min-h-screen flex-col">
    <a
      href="#main"
      @click="skipToMain"
      class="sr-only rounded-md bg-surface px-4 py-2 text-sm font-semibold focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50"
    >
      Skip to content
    </a>
    <AppHeader />
    <main id="main" tabindex="-1" class="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-6 lg:py-14">
      <RouterView />
    </main>
    <AppFooter />
  </div>
</template>
