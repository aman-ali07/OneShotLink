<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch, type Ref } from "vue";
import { useRoute } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import { ttlLabel } from "@/lib/format";
import {
  ApiError,
  errorMessage,
  getRequest,
  respondToRequest,
  type RequestPreview,
} from "@/lib/api";

const route = useRoute();
const key = () => String(route.params.key ?? "");
const phase = ref<"loading" | "ready" | "sent" | "gone" | "taken" | "error">("loading");
const preview = ref<RequestPreview | null>(null);
const secret = ref("");
const error = ref("");
const submitting = ref(false);
const sentHeading = ref<HTMLHeadingElement | null>(null);
const goneHeading = ref<HTMLHeadingElement | null>(null);
const takenHeading = ref<HTMLHeadingElement | null>(null);
const errorHeading = ref<HTMLHeadingElement | null>(null);
let peekController: AbortController | undefined;

async function focusHeading(target: Ref<HTMLHeadingElement | null>) {
  await nextTick();
  target.value?.focus();
}

function reload() {
  window.location.reload();
}

async function load() {
  peekController?.abort();
  peekController = new AbortController();
  try {
    preview.value = await getRequest(key(), peekController.signal);
    if (peekController.signal.aborted) return;
    phase.value = preview.value.fulfilled ? "taken" : "ready";
    if (phase.value === "taken") await focusHeading(takenHeading);
  } catch (cause) {
    if (peekController?.signal.aborted) return;
    if (cause instanceof ApiError && cause.status === 404) {
      phase.value = "gone";
      await focusHeading(goneHeading);
    } else {
      // A transport/500/429 failure must not render "Send a secret to " with a
      // blank label. Show a recoverable terminal panel instead.
      error.value = errorMessage(cause);
      phase.value = "error";
      await focusHeading(errorHeading);
    }
  }
}

onMounted(load);

// The router reuses this component across /request/:key navigations. Without a
// watch a second link inherits the previous key's terminal phase and answer.
watch(() => route.params.key, () => {
  phase.value = "loading";
  preview.value = null;
  secret.value = "";
  error.value = "";
  void load();
});

onBeforeUnmount(() => {
  // The submitted answer is a secret. Drop it when the responder leaves.
  secret.value = "";
  peekController?.abort();
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
    await focusHeading(sentHeading);
  } catch (cause) {
    if (cause instanceof ApiError && cause.status === 409) {
      secret.value = "";
      phase.value = "taken";
      await focusHeading(takenHeading);
    } else if (cause instanceof ApiError && cause.status === 404) {
      // The answer is a secret; do not keep it in memory once the form is gone.
      secret.value = "";
      phase.value = "gone";
      await focusHeading(goneHeading);
    } else error.value = errorMessage(cause);
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
        <h1 id="request-gone-heading" ref="goneHeading" tabindex="-1" class="ots-title-compact">This request is closed</h1>
        <p class="text-muted">It expired or was removed. Ask the sender for a new link.</p>
      </div>
    </section>

    <section v-else-if="phase === 'taken'" class="ots-panel overflow-hidden" aria-labelledby="request-taken-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Already answered</span></div>
      <div class="space-y-4 px-6 py-10">
        <h1 id="request-taken-heading" ref="takenHeading" tabindex="-1" class="ots-title-compact">A secret was already sent</h1>
        <p class="text-muted">Each request link accepts one answer. You do not need to send anything again.</p>
      </div>
    </section>

    <section v-else-if="phase === 'sent'" class="ots-panel overflow-hidden" aria-labelledby="request-sent-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Delivered</span></div>
      <div class="space-y-5 px-6 py-10">
        <h1 id="request-sent-heading" ref="sentHeading" tabindex="-1" class="ots-title-compact">Your secret was sent</h1>
        <p class="text-muted">
          The recipient can open it once. It has been deleted from the server after that view,
          so keep a copy if you need one.
        </p>
        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Share a secret of your own
        </RouterLink>
      </div>
    </section>

    <section v-else-if="phase === 'error'" class="ots-panel overflow-hidden" aria-labelledby="request-error-heading">
      <div class="border-b border-border px-6 py-4"><span class="ots-eyebrow">Could not open</span></div>
      <div class="space-y-5 px-6 py-10">
        <h1 id="request-error-heading" ref="errorHeading" tabindex="-1" class="ots-title-compact">This link could not be loaded</h1>
        <AppAlert tone="danger">{{ error }}</AppAlert>
        <AppButton type="button" @click="reload">Try again</AppButton>
      </div>
    </section>

    <section v-else class="ots-panel overflow-hidden" aria-labelledby="request-heading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4">
        <span class="ots-eyebrow shrink-0 whitespace-nowrap">Incoming request</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">One answer allowed</span>
      </div>
      <div class="grid gap-8 px-6 py-9 sm:px-8 lg:grid-cols-[minmax(0,1fr)_15rem]">
        <div class="space-y-6">
          <div class="space-y-2">
            <h1 id="request-heading" class="ots-title">
              Send a secret to {{ preview?.metadata.label }}
            </h1>
            <p class="text-muted">The recipient asked for one secret through this link. It works once.</p>
          </div>

          <AppAlert v-if="error" id="request-secret-error" tone="danger">{{ error }}</AppAlert>

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
                :aria-describedby="error ? 'request-secret-help request-secret-error' : 'request-secret-help'"
              />
              <p id="request-secret-help" class="text-xs text-muted">Never put secrets in the URL or in an email.</p>
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
