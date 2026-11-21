<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import { errorMessage, signUp } from "@/lib/api";
import { accountsEnabled } from "@/lib/authMode";

const email = ref("");
const password = ref("");
const confirmation = ref("");
const submitting = ref(false);
const error = ref("");
const router = useRouter();
const available = ref(true);

onMounted(async () => {
  available.value = await accountsEnabled();
});

async function submit() {
  error.value = "";
  if (new TextEncoder().encode(password.value).length < 12) {
    error.value = "Choose a password with at least 12 bytes.";
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
  <section class="ots-panel ots-enter mx-auto max-w-lg space-y-6 p-7 sm:p-9">
    <p class="ots-eyebrow">Account / Create</p>
    <div class="space-y-2">
      <h1 class="ots-title">Create an account</h1>
      <p class="text-muted">
        Optional. You can share secrets without an account.
      </p>
    </div>

    <AppAlert v-if="!available">
      Accounts are off on this instance. You can create secret links without an account.
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
          autocomplete="new-password"
          maxlength="256"
          required
          :aria-describedby="error ? 'password-help signup-error' : 'password-help'"
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
        <p id="password-help" class="text-xs text-muted">At least 12 bytes.</p>
      </div>

      <div class="space-y-2">
        <label for="confirmation" class="block text-sm font-semibold">Confirm password</label>
        <input
          id="confirmation"
          v-model="confirmation"
          type="password"
          autocomplete="new-password"
          required
          :aria-describedby="error ? 'signup-error' : undefined"
          class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
        />
      </div>

      <AppAlert v-if="error" id="signup-error" tone="danger">{{ error }}</AppAlert>

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
