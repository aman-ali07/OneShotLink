<script setup lang="ts">
import AppFooter from "@/components/AppFooter.vue";
import AppHeader from "@/components/AppHeader.vue";
</script>

<template>
  <div class="flex min-h-screen flex-col">
    <a
      href="#main"
      class="sr-only rounded-md bg-surface px-4 py-2 text-sm font-semibold focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50"
    >
      Skip to content
    </a>
    <AppHeader />
    <main id="main" class="mx-auto w-full max-w-3xl flex-1 px-4 py-10 sm:px-6">
      <RouterView />
    </main>
    <AppFooter />
  </div>
</template>
