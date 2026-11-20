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

function sizeLabel(value: number): string {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

const isFile = () => revealed.value?.metadata.kind === "file";
const downloadName = () => revealed.value?.metadata.filename || "secret.bin";

function decodedSize(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((base64.length * 3) / 4) - padding);
}

// The payload is base64 because Crypto.decrypt forces UTF-8 on the record.
// Decode to bytes here so arbitrary binary files survive the last hop.
function downloadFile() {
  if (!revealed.value || !isFile()) return;
  const binary = atob(revealed.value.secret_value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  const url = URL.createObjectURL(new Blob([bytes], { type: "application/octet-stream" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = downloadName();
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
</script>

<template>
  <div class="ots-enter mx-auto max-w-3xl">
    <section v-if="phase === 'gone'" class="ots-panel overflow-hidden" aria-labelledby="gone-heading">
      <div class="border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">Terminal state</span>
      </div>
      <div class="space-y-5 px-6 py-10 sm:px-8">
        <div class="flex h-11 w-11 items-center justify-center rounded-full bg-border text-muted" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
            <path d="M6 6l12 12M18 6 6 18" />
          </svg>
        </div>
        <h1 id="gone-heading" class="text-3xl font-bold tracking-tight">This secret is gone</h1>
        <p class="max-w-lg leading-relaxed text-muted">
          It was already opened, it expired, or it never existed. The server does not say which.
        </p>
        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Create a new secret
        </RouterLink>
      </div>
    </section>

    <section v-else-if="phase === 'revealed' && revealed" class="ots-panel overflow-hidden" aria-labelledby="revealed-heading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">The secret</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">Shown once</span>
      </div>
      <div class="space-y-7 px-6 py-9 sm:px-8">
        <div class="space-y-3">
          <h1 id="revealed-heading" ref="revealHeading" tabindex="-1" class="text-3xl font-bold tracking-tight sm:text-4xl">
            Your secret
          </h1>
          <p class="text-muted">
            {{ isFile() ? "Download it now." : "Copy it now." }}
            It has been deleted from the server and cannot be shown again.
          </p>
        </div>

        <div v-if="isFile()" class="ots-inset space-y-4 p-5" aria-labelledby="file-name">
          <div class="flex items-start gap-4">
            <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-accent/10 text-accent" aria-hidden="true">
              <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6" />
              </svg>
            </div>
            <div class="min-w-0 space-y-1">
              <p id="file-name" class="truncate font-semibold text-text">{{ downloadName() }}</p>
              <p class="text-xs text-muted">{{ sizeLabel(decodedSize(revealed.secret_value)) }} · binary file</p>
            </div>
          </div>
          <AppButton type="button" @click="downloadFile">Download file</AppButton>
          <p class="text-xs text-muted">The download is decoded in your browser. Do not reload — the file is already gone from the server.</p>
        </div>
        <div v-else class="ots-inset space-y-4 p-5">
          <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-words font-mono text-sm text-text">{{ revealed.secret_value }}</pre>
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
      </div>
    </section>

    <section v-else class="ots-panel overflow-hidden" aria-labelledby="reveal-heading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">03 / Open</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">One-time link</span>
      </div>
      <div class="grid gap-8 px-6 py-9 sm:px-8 lg:grid-cols-[minmax(0,1fr)_15rem]">
        <div class="space-y-6">
          <div class="space-y-3">
            <h1 id="reveal-heading" class="text-3xl font-bold tracking-tight sm:text-4xl">
              A secret was shared with you
            </h1>
            <p class="text-muted">It can be opened once. Opening it deletes it.</p>
          </div>

          <AppAlert>
            Your browser previewed this link without opening the secret. Nothing has been spent.
            Do not reload after revealing — the value cannot be shown again.
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
                class="ots-inset w-full px-3 py-2.5 text-sm"
              />
              <p class="text-xs text-muted">The sender should have given this to you separately.</p>
            </div>

            <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

            <AppButton type="submit" :loading="loading">
              {{ loading ? "Revealing…" : "Reveal secret" }}
            </AppButton>
          </form>
        </div>

        <aside class="ots-inset h-fit space-y-3 p-5 text-sm text-muted" aria-label="Before you reveal">
          <p class="font-semibold text-text">Before you reveal</p>
          <p>Make sure you can store the value somewhere safe. After this confirmation there is no second view.</p>
          <p class="text-xs">A passphrase, if one was set, is an extra check — not a second encryption key.</p>
        </aside>
      </div>
    </section>
  </div>
</template>
