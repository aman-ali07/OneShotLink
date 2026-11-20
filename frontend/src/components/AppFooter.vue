<template>
  <footer class="mt-auto border-t border-border bg-surface/70">
    <div class="mx-auto grid max-w-6xl gap-6 px-4 py-8 text-xs text-muted sm:grid-cols-3 sm:px-6">
      <div class="space-y-2">
        <p class="text-sm font-semibold text-text">OneShotLink</p>
        <p class="max-w-xs leading-relaxed">
          Encrypted at rest. Deleted after one view or on expiry. Self-hosted by the people who
          need it.
        </p>
      </div>
      <div class="space-y-1">
        <p class="font-semibold text-text">Product</p>
        <RouterLink to="/" class="inline-flex min-h-6 items-center hover:text-accent">New secret</RouterLink>
        <RouterLink to="/dashboard" class="inline-flex min-h-6 items-center hover:text-accent">Account</RouterLink>
      </div>
      <div class="space-y-1">
        <p class="font-semibold text-text">Developers</p>
        <a href="/api/v3/openapi.json" class="inline-flex min-h-6 items-center hover:text-accent">OpenAPI document</a>
        <a href="https://github.com/aman-ali07/OneShotLink/blob/main/docs/SDK.md" class="inline-flex min-h-6 items-center hover:text-accent">SDK guide</a>
        <a href="https://github.com/aman-ali07/OneShotLink" class="inline-flex min-h-6 items-center hover:text-accent">Source</a>
      </div>
    </div>
  </footer>
</template>
