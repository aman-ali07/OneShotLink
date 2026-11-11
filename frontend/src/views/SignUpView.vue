<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import { errorMessage, signUp } from "@/lib/api";

const email = ref("");
const password = ref("");
const confirmation = ref("");
const submitting = ref(false);
const error = ref("");
const router = useRouter();

async function submit() {
  error.value = "";
  if (new TextEncoder().encode(password.value).length < 12) {
    error.value = "Choose a password with at least 12 characters.";
    return;
  }
  if (password.value !== confirmation.value) {
    error.value = "The passwords do not match.";
    return;
  }

  submitting.value = true;
  try {
    await signUp({ email: email.value, password: password.value });
    password.value = "";
    confirmation.value = "";
    await router.push("/dashboard");
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
      <h1 class="text-3xl font-bold tracking-tight">Create an account</h1>
      <p class="text-muted">
        Optional. You can share secrets without an account.
      </p>
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
          autocomplete="new-password"
          minlength="12"
          maxlength="256"
          required
          aria-describedby="password-help"
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
        <p id="password-help" class="text-xs text-muted">At least 12 characters.</p>
      </div>

      <div class="space-y-2">
        <label for="confirmation" class="block text-sm font-semibold">Confirm password</label>
        <input
          id="confirmation"
          v-model="confirmation"
          type="password"
          autocomplete="new-password"
          required
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
      </div>

      <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

      <AppButton type="submit" :loading="submitting">
        {{ submitting ? "Creating account…" : "Create account" }}
      </AppButton>
    </form>

    <p class="text-sm text-muted">
      Already have an account?
      <RouterLink to="/signin" class="font-medium text-accent underline underline-offset-2">
        Sign in
      </RouterLink>
    </p>
  </section>
</template>
