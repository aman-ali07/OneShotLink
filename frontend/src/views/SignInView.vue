<script setup lang="ts">
import { ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import { errorMessage, signIn } from "@/lib/api";

const email = ref("");
const password = ref("");
const submitting = ref(false);
const error = ref("");
const route = useRoute();
const router = useRouter();

function redirectTarget(): string {
  const target = typeof route.query.redirect === "string" ? route.query.redirect : "/dashboard";
  return target.startsWith("/") && !target.startsWith("//") ? target : "/dashboard";
}

async function submit() {
  error.value = "";
  submitting.value = true;
  try {
    await signIn({ email: email.value, password: password.value });
    password.value = "";
    await router.push(redirectTarget());
  } catch (cause) {
    error.value = errorMessage(cause);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <section class="mx-auto max-w-md space-y-6">
    <div class="space-y-2">
      <h1 class="text-3xl font-bold tracking-tight">Sign in</h1>
      <p class="text-muted">See the secret links you have created.</p>
    </div>

    <form class="space-y-4" @submit.prevent="submit">
      <div class="space-y-2">
        <label for="email" class="block text-sm font-semibold">Email</label>
        <input
          id="email"
          v-model="email"
          type="email"
          autocomplete="email"
          required
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
      </div>

      <div class="space-y-2">
        <label for="password" class="block text-sm font-semibold">Password</label>
        <input
          id="password"
          v-model="password"
          type="password"
          autocomplete="current-password"
          required
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
      </div>

      <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

      <AppButton type="submit" :loading="submitting">
        {{ submitting ? "Signing in…" : "Sign in" }}
      </AppButton>
    </form>

    <p class="text-sm text-muted">
      No account?
      <RouterLink to="/signup" class="font-medium text-accent underline underline-offset-2">
        Create one
      </RouterLink>
    </p>
  </section>
</template>
