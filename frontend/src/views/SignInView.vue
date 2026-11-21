<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import { errorMessage, signIn } from "@/lib/api";
import { accountsEnabled } from "@/lib/authMode";

const email = ref("");
const password = ref("");
const submitting = ref(false);
const error = ref("");
const route = useRoute();
const router = useRouter();
const available = ref(true);

onMounted(async () => {
  available.value = await accountsEnabled();
});

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
  <section class="ots-panel ots-enter mx-auto max-w-lg space-y-6 p-7 sm:p-9">
    <p class="ots-eyebrow">Account / Sign in</p>
    <div class="space-y-2">
      <h1 class="ots-title">Sign in</h1>
      <p class="text-muted">See the secret links you have created.</p>
    </div>

    <AppAlert v-if="!available">
      Accounts are off on this instance. You can still create and open secret links without one.
      <RouterLink to="/" class="font-semibold underline underline-offset-2">Create a secret</RouterLink>
    </AppAlert>

    <form v-if="available" class="space-y-4" @submit.prevent="submit">
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
          :aria-describedby="error ? 'signin-error' : undefined"
        />
      </div>

      <AppAlert v-if="error" id="signin-error" tone="danger">{{ error }}</AppAlert>

      <AppButton type="submit" :loading="submitting">
        {{ submitting ? "Signing in…" : "Sign in" }}
      </AppButton>
    </form>

    <p v-if="available" class="text-sm text-muted">
      No account?
      <RouterLink to="/signup" class="font-medium text-accent underline underline-offset-2">
        Create one
      </RouterLink>
    </p>
  </section>
</template>
