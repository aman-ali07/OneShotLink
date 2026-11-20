<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import {
  ApiError,
  errorMessage,
  getRequest,
  respondToRequest,
  type RequestPreview,
} from "@/lib/api";

const route = useRoute();
const key = () => String(route.params.key ?? "");
const phase = ref<"loading" | "ready" | "sent" | "gone" | "taken">("loading");
const preview = ref<RequestPreview | null>(null);
const secret = ref("");
const error = ref("");
const submitting = ref(false);

function ttlLabel(seconds: number): string {
  if (seconds < 3600) return `${Math.round(seconds / 60)} minutes`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} hours`;
  return `${Math.round(seconds / 86400)} day${seconds >= 172800 ? "s" : ""}`;
}

onMounted(async () => {
  try {
    preview.value = await getRequest(key());
    phase.value = preview.value.fulfilled ? "taken" : "ready";
  } catch (cause) {
    phase.value = cause instanceof ApiError && cause.status === 404 ? "gone" : "ready";
    if (!(cause instanceof ApiError && cause.status === 404)) {
      error.value = errorMessage(cause);
    }
  }
});

async function submit() {
  error.value = "";
  if (secret.value === "") {
    error.value = "Enter the secret you want to send.";
    return;
  }
  submitting.value = true;
  try {
    await respondToRequest(key(), secret.value);
    secret.value = "";
    phase.value = "sent";
  } catch (cause) {
    if (cause instanceof ApiError && cause.status === 409) phase.value = "taken";
    else if (cause instanceof ApiError && cause.status === 404) phase.value = "gone";
    else error.value = errorMessage(cause);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="ots-enter mx-auto max-w-2xl">
    <section v-if="phase === 'loading'" class="ots-panel space-y-4 p-8" aria-busy="true" aria-live="polite">
      <p class="ots-eyebrow">Incoming request</p>
      <div class="h-8 w-56 animate-pulse rounded bg-border" aria-hidden="true" />
      <div class="h-4 w-80 animate-pulse rounded bg-border" aria-hidden="true" />
      <span class="sr-only">Loading the request…</span>
    </section>

    <section v-else-if="phase === 'gone'" class="ots-panel overflow-hidden" aria-labelledby="request-gone-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Terminal state</span></div>
      <div class="space-y-4 px-6 py-10">
        <h1 id="request-gone-heading" class="text-3xl font-bold tracking-tight">This request is closed</h1>
        <p class="text-muted">It expired or was removed. Ask the sender for a new link.</p>
      </div>
    </section>

    <section v-else-if="phase === 'taken'" class="ots-panel overflow-hidden" aria-labelledby="request-taken-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Already answered</span></div>
      <div class="space-y-4 px-6 py-10">
        <h1 id="request-taken-heading" class="text-3xl font-bold tracking-tight">A secret was already sent</h1>
        <p class="text-muted">Each request link accepts one answer. You do not need to send anything again.</p>
      </div>
    </section>

    <section v-else-if="phase === 'sent'" class="ots-panel overflow-hidden" aria-labelledby="request-sent-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Delivered</span></div>
      <div class="space-y-5 px-6 py-10">
        <h1 id="request-sent-heading" tabindex="-1" class="text-3xl font-bold tracking-tight">Your secret was sent</h1>
        <p class="text-muted">
          The recipient can open it once. It has been deleted from the server after that view,
          so keep a copy if you need one.
        </p>
        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Share a secret of your own
        </RouterLink>
      </div>
    </section>

    <section v-else class="ots-panel overflow-hidden" aria-labelledby="request-heading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4">
        <span class="ots-eyebrow">Incoming request</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">One answer allowed</span>
      </div>
      <div class="grid gap-8 px-6 py-9 sm:px-8 lg:grid-cols-[minmax(0,1fr)_15rem]">
        <div class="space-y-6">
          <div class="space-y-2">
            <h1 id="request-heading" class="text-3xl font-bold tracking-tight sm:text-4xl">
              Send a secret to {{ preview?.metadata.label }}
            </h1>
            <p class="text-muted">The recipient asked for one secret through this link. It works once.</p>
          </div>

          <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

          <form class="space-y-5" @submit.prevent="submit">
            <div class="space-y-2">
              <label for="request-secret" class="block text-sm font-semibold">Secret</label>
              <textarea
                id="request-secret"
                v-model="secret"
                rows="7"
                spellcheck="false"
                autocomplete="off"
                class="ots-inset w-full resize-y p-3 font-mono text-sm text-text"
                placeholder="Paste the value you want to send…"
              />
              <p class="text-xs text-muted">Never put secrets in the URL or in an email.</p>
            </div>
            <AppButton type="submit" :loading="submitting">
              {{ submitting ? "Sending…" : "Send secret" }}
            </AppButton>
          </form>
        </div>

        <aside class="ots-inset h-fit space-y-3 p-5 text-sm text-muted">
          <p class="font-semibold text-text">What to expect</p>
          <p>Your answer is encrypted before it is stored and can be opened once by the recipient.</p>
          <p v-if="preview" class="text-xs">This request expires in {{ ttlLabel(preview.metadata.ttl) }}.</p>
          <p class="text-xs">The server holds the encryption key. This is not client-side encryption.</p>
        </aside>
      </div>
    </section>
  </div>
</template>
