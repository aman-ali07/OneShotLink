<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRoute } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import CopyButton from "@/components/CopyButton.vue";
import { formatTimestamp, sizeLabel, ttlLabel } from "@/lib/format";
import { ApiError, errorMessage, peekSecret, revealSecret, type RevealResponse, type SecretPreview } from "@/lib/api";

type Phase = "idle" | "passphrase" | "revealed" | "gone" | "invalid";

const route = useRoute();
const phase = ref<Phase>("idle");
const loading = ref(false);
const error = ref("");
const passphrase = ref("");
const revealed = ref<RevealResponse | null>(null);
const passphraseInput = ref<HTMLInputElement | null>(null);
const revealHeading = ref<HTMLHeadingElement | null>(null);
const goneHeading = ref<HTMLHeadingElement | null>(null);
const invalidHeading = ref<HTMLHeadingElement | null>(null);
const preview = ref<SecretPreview | null>(null);
const previewNote = ref("");
let peekController: AbortController | undefined;

// Plaintext lives only in component state. Drop it when the view is left, not
// just when the user presses Hide (DESIGN_SYSTEM.md §6).
onBeforeUnmount(() => {
  revealed.value = null;
  peekController?.abort();
});

const key = () => String(route.params.key ?? "");

function reset() {
  phase.value = "idle";
  loading.value = false;
  error.value = "";
  passphrase.value = "";
  revealed.value = null;
  preview.value = null;
  previewNote.value = "";
  peekController?.abort();
}

// GET is a metadata-only preview: it never decrypts or consumes the secret.
// Using it lets us present the passphrase/gone state before a POST and avoids
// spending a reveal attempt on a link that is already gone.
async function load() {
  peekController?.abort();
  peekController = new AbortController();
  const controller = peekController;
  try {
    const meta = await peekSecret(key(), controller.signal);
    if (controller.signal.aborted) return;
    preview.value = meta;
    if (meta.passphrase_required) {
      phase.value = "passphrase";
      await nextTick();
      passphraseInput.value?.focus();
    }
  } catch (cause) {
    if (controller.signal.aborted) return;
    if (cause instanceof ApiError && cause.code === "not_found") {
      phase.value = "gone";
      revealed.value = null;
      await nextTick();
      goneHeading.value?.focus();
    } else if (cause instanceof ApiError && cause.status === 422) {
      phase.value = "invalid";
      revealed.value = null;
      await nextTick();
      invalidHeading.value?.focus();
    } else {
      // A preview failure is not fatal: the explicit reveal still works.
      previewNote.value = "Could not check this link's status. You can still try to reveal it.";
    }
  }
}

onMounted(load);

// The router reuses this component across /secret/:key navigations. Reset the
// terminal phase and peek the new key instead of inheriting the old one.
watch(() => route.params.key, () => {
  reset();
  void load();
});

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
      // Keep the field, but clear the wrong value so a retry is one type, not
      // a select-all/delete gesture on mobile.
      passphrase.value = "";
      await nextTick();
      passphraseInput.value?.focus();
    } else if (cause instanceof ApiError && cause.code === "not_found") {
      phase.value = "gone";
      revealed.value = null;
      await nextTick();
      goneHeading.value?.focus();
    } else if (cause instanceof ApiError && cause.status === 422) {
      // A malformed key (too long/invalid) is distinct from a consumed or
      // expired one: tell the recipient the link itself is broken.
      phase.value = "invalid";
      revealed.value = null;
      await nextTick();
      invalidHeading.value?.focus();
    } else {
      error.value = errorMessage(cause);
    }
  } finally {
    loading.value = false;
  }
}

// The server has already deleted the secret at this point. Hiding it removes
// the plaintext from the screen without implying it can be shown again.
async function hideSecret() {
  revealed.value = null;
  phase.value = "gone";
  await nextTick();
  goneHeading.value?.focus();
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
  // Defer revocation: some browsers cancel a download whose object URL is
  // revoked in the same task as the click.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
</script>

<template>
  <div class="ots-enter mx-auto max-w-3xl">
    <section v-if="phase === 'invalid'" class="ots-panel overflow-hidden" aria-labelledby="invalid-heading">
      <div class="border-b border-border px-6 py-4 sm:px-8"><span class="ots-eyebrow">Invalid link</span></div>
      <div class="space-y-5 px-6 py-10 sm:px-8">
        <h1 id="invalid-heading" ref="invalidHeading" tabindex="-1" class="ots-title-compact">This link is not valid</h1>
        <p class="max-w-lg leading-relaxed text-muted">
          The address is malformed. Check that you copied the whole link and ask the sender for a new one.
        </p>
        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Ask the sender for a new link
        </RouterLink>
      </div>
    </section>

    <section v-else-if="phase === 'gone'" class="ots-panel overflow-hidden" aria-labelledby="gone-heading">
      <div class="border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">Terminal state</span>
      </div>
      <div class="space-y-5 px-6 py-10 sm:px-8">
        <div class="flex h-11 w-11 items-center justify-center rounded-full bg-border text-muted" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
            <path d="M6 6l12 12M18 6 6 18" />
          </svg>
        </div>
        <h1 id="gone-heading" ref="goneHeading" tabindex="-1" class="ots-title-compact">This secret is gone</h1>
        <p class="max-w-lg leading-relaxed text-muted">
          It was already opened, it expired, or it never existed. The server does not say which.
        </p>
        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Ask the sender for a new link
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
          <h1 id="revealed-heading" ref="revealHeading" tabindex="-1" class="ots-title-compact">
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

        <AppButton variant="secondary" type="button" @click="hideSecret">Hide secret</AppButton>

        <AppAlert tone="success">
          Permanently deleted on the server.
          <span v-if="formatTimestamp(revealed.metadata.created_at)">
            Shared on {{ formatTimestamp(revealed.metadata.created_at) }}, with a
            {{ ttlLabel(revealed.metadata.ttl) }} lifetime.
          </span>
        </AppAlert>

        <RouterLink to="/" class="inline-block text-sm font-semibold text-accent hover:underline">
          Share a secret of your own
        </RouterLink>
      </div>
    </section>

    <section v-else class="ots-panel overflow-hidden" aria-labelledby="reveal-heading" :aria-busy="loading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">03 / Open</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">One-time link</span>
      </div>
      <div class="grid gap-8 px-6 py-9 sm:px-8 lg:grid-cols-[minmax(0,1fr)_15rem]">
        <div class="space-y-6">
          <div class="space-y-3">
            <h1 id="reveal-heading" class="ots-title">
              A secret was shared with you
            </h1>
            <p class="text-muted">If this link is still valid, you can open it once. Opening it deletes it.</p>
          </div>

          <AppAlert v-if="preview">
            <span v-if="preview.metadata.filename">File: {{ preview.metadata.filename }} · </span>
            <span v-else-if="preview.metadata.kind === 'file'">File secret · </span>
            <span v-else>Text secret · </span>
            <span v-if="formatTimestamp(preview.metadata.created_at ?? null)">Shared {{ formatTimestamp(preview.metadata.created_at ?? null) }} · </span>
            Lifetime {{ ttlLabel(preview.metadata.ttl) }}. A link preview cannot open it; nothing has been spent yet.
          </AppAlert>
          <AppAlert v-else-if="previewNote">{{ previewNote }}</AppAlert>
          <AppAlert v-else>
            A link preview cannot open the secret. Nothing has been spent until you confirm.
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
                :aria-describedby="error ? 'reveal-passphrase-help reveal-passphrase-error' : 'reveal-passphrase-help'"
              />
              <p id="reveal-passphrase-help" class="text-xs text-muted">The sender should have given this to you separately.</p>
            </div>

            <AppAlert v-if="error" id="reveal-passphrase-error" tone="danger">{{ error }}</AppAlert>

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
