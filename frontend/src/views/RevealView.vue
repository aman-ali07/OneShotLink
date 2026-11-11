<script setup lang="ts">
import { nextTick, ref, watch } from "vue";
import { useRoute } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import CopyButton from "@/components/CopyButton.vue";
import { ApiError, errorMessage, revealSecret, type RevealResponse } from "@/lib/api";

type Phase = "idle" | "passphrase" | "revealed" | "gone";

const route = useRoute();
const phase = ref<Phase>("idle");
const loading = ref(false);
const error = ref("");
const passphrase = ref("");
const revealed = ref<RevealResponse | null>(null);
const passphraseInput = ref<HTMLInputElement | null>(null);
const revealHeading = ref<HTMLHeadingElement | null>(null);

const key = () => String(route.params.key ?? "");

function reset() {
  phase.value = "idle";
  loading.value = false;
  error.value = "";
  passphrase.value = "";
  revealed.value = null;
}

watch(() => route.params.key, reset);

async function reveal() {
  if (loading.value || phase.value === "revealed" || phase.value === "gone") return;
  error.value = "";
  loading.value = true;

  try {
    revealed.value = await revealSecret(
      key(),
      phase.value === "passphrase" ? passphrase.value : undefined,
    );
    phase.value = "revealed";
    passphrase.value = "";
    await nextTick();
    revealHeading.value?.focus();
  } catch (cause) {
    if (cause instanceof ApiError && cause.code === "passphrase_required") {
      phase.value = "passphrase";
      await nextTick();
      passphraseInput.value?.focus();
    } else if (cause instanceof ApiError && cause.code === "invalid_passphrase") {
      phase.value = "passphrase";
      error.value = cause.message;
      await nextTick();
      passphraseInput.value?.focus();
    } else if (cause instanceof ApiError && cause.code === "not_found") {
      phase.value = "gone";
    } else {
      error.value = errorMessage(cause);
    }
  } finally {
    loading.value = false;
  }
}

function sharedOn(seconds: number | null): string | null {
  if (!seconds) return null;
  return new Date(seconds * 1000).toLocaleString();
}

function ttlLabel(seconds: number): string {
  if (seconds < 3600) return `${Math.round(seconds / 60)} minutes`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} hours`;
  return `${Math.round(seconds / 86400)} day${seconds >= 172800 ? "s" : ""}`;
}
</script>

<template>
  <div class="space-y-8">
    <section v-if="phase === 'gone'" class="space-y-4" aria-labelledby="gone-heading">
      <h1 id="gone-heading" class="text-3xl font-bold tracking-tight">This secret is gone</h1>
      <p class="text-muted">
        It was already viewed, has expired, or never existed. For safety, the server does not
        say which.
      </p>
      <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
        Create a new secret
      </RouterLink>
    </section>

    <section v-else-if="phase === 'revealed' && revealed" class="space-y-6" aria-labelledby="revealed-heading">
      <div class="space-y-2">
        <h1 id="revealed-heading" ref="revealHeading" tabindex="-1" class="text-3xl font-bold tracking-tight">
          Your secret
        </h1>
        <p class="text-muted">Copy it now. It has been deleted from the server and cannot be shown again.</p>
      </div>

      <div class="space-y-3 rounded-md border border-border bg-surface p-4 shadow-card">
        <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-words font-mono text-sm">{{ revealed.secret_value }}</pre>
        <CopyButton :text="revealed.secret_value" label="Copy secret" />
      </div>

      <AppAlert tone="success">
        Permanently deleted on the server.
        <span v-if="sharedOn(revealed.metadata.created_at)">
          Shared on {{ sharedOn(revealed.metadata.created_at) }}, with a
          {{ ttlLabel(revealed.metadata.ttl) }} lifetime.
        </span>
      </AppAlert>

      <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
        Share a secret of your own
      </RouterLink>
    </section>

    <section v-else class="space-y-6" aria-labelledby="reveal-heading">
      <div class="space-y-2">
        <h1 id="reveal-heading" class="text-3xl font-bold tracking-tight">A secret was shared with you</h1>
        <p class="text-muted">It can be viewed once. Reading it will destroy it immediately.</p>
      </div>

      <AppAlert>
        Do not reload the page after revealing. Reloading will not show the secret again.
      </AppAlert>

      <form class="space-y-5" @submit.prevent="reveal">
        <div v-if="phase === 'passphrase'" class="space-y-2">
          <label for="reveal-passphrase" class="block text-sm font-semibold">Passphrase</label>
          <input
            id="reveal-passphrase"
            ref="passphraseInput"
            v-model="passphrase"
            type="password"
            autocomplete="current-password"
            class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
          />
          <p class="text-xs text-muted">The sender should have given this to you separately.</p>
        </div>

        <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

        <AppButton type="submit" :loading="loading">
          {{ loading ? "Revealing…" : "Reveal secret" }}
        </AppButton>
      </form>
    </section>
  </div>
</template>
