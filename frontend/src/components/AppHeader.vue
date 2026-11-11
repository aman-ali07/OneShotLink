<template>
  <header class="border-b border-border bg-bg">
    <div class="mx-auto flex h-16 max-w-3xl items-center justify-between px-4 sm:px-6">
      <RouterLink to="/" class="text-base font-semibold tracking-tight text-text">
        One-time secret
      </RouterLink>
      <nav aria-label="Primary">
        <RouterLink
          to="/"
          class="rounded-md px-3 py-2 text-sm font-medium text-muted hover:text-text"
        >
          New secret
        </RouterLink>
        <RouterLink
          to="/dashboard"
          class="rounded-md px-3 py-2 text-sm font-medium text-muted hover:text-text"
        >
          Account
        </RouterLink>
      </nav>
    </div>
  </header>
</template>
