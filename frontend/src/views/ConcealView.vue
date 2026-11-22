<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from "vue";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import CopyButton from "@/components/CopyButton.vue";
import { sizeLabel, ttlLabel } from "@/lib/format";
import { publicConfig } from "@/lib/config";
import {
  concealSecret,
  errorMessage,
  type ConcealResponse,
} from "@/lib/api";

const secret = ref("");
const mode = ref<"text" | "file">("text");
// A misclick on the File tab must not destroy a pasted secret.
const textDraft = ref("");
const readingFile = ref(false);
const chosenFile = ref<File | null>(null);
const fileName = ref("");
// Server values only. No hardcoded TTL/limit seeds: an operator may change
// TTL_OPTIONS or MAX_SECRET_BYTES and the UI must follow the served config.
const maxFileBytes = ref(0);
const ttl = ref(0);
const passphrase = ref("");
const ttlOptions = ref<number[]>([]);
const maxBytes = ref(0);
const configReady = ref(false);
const submitting = ref(false);
const error = ref("");
const configNote = ref("");
const result = ref<ConcealResponse | null>(null);
const resultHeading = ref<HTMLHeadingElement | null>(null);
const secretInput = ref<HTMLTextAreaElement | null>(null);

const bytes = computed(() => new TextEncoder().encode(secret.value).length);
const payloadBytes = computed(() => chosenFile.value?.size ?? bytes.value);
const limitBytes = computed(() => (mode.value === "file" ? maxFileBytes.value : maxBytes.value));
// Keep the true ratio for the colour decision — clamping it to 100 made the
// over-limit branch unreachable, so an oversized paste showed amber, not red.
const usageRaw = computed(() => Math.round((payloadBytes.value / limitBytes.value) * 100));
const usage = computed(() => Math.min(100, usageRaw.value));
const link = computed(() => {
  if (!result.value) return "";
  return new URL(result.value.links.secret, window.location.origin).toString();
});

function setMode(next: "text" | "file") {
  if (mode.value === next) return;
  if (mode.value === "text") textDraft.value = secret.value;
  mode.value = next;
  secret.value = next === "text" ? textDraft.value : "";
  chosenFile.value = null;
  fileName.value = "";
  error.value = "";
}

async function chooseFile(event: Event) {
  const input = event.target as HTMLInputElement;
  const chosen = input.files?.[0] ?? null;
  error.value = "";
  secret.value = "";
  chosenFile.value = null;
  fileName.value = "";
  if (!chosen) return;
  if (chosen.size > maxFileBytes.value) {
    error.value = `Files must be at most ${sizeLabel(maxFileBytes.value)}.`;
    input.value = "";
    return;
  }

  // Base64 stays ASCII, so the existing AES-GCM path (which forces UTF-8 on
  // decrypt) cannot corrupt the original bytes. Encoding a 512 KiB file is
  // visible work, so show a live status while it runs.
  readingFile.value = true;
  try {
    const view = new Uint8Array(await chosen.arrayBuffer());
    let binary = "";
    const CHUNK = 0x8000;
    for (let i = 0; i < view.length; i += CHUNK) {
      binary += String.fromCharCode(...view.subarray(i, i + CHUNK));
    }
    secret.value = btoa(binary);
    chosenFile.value = chosen;
    fileName.value = chosen.name;
  } catch {
    error.value = "Could not read that file. Try again.";
  } finally {
    readingFile.value = false;
  }
}

onMounted(async () => {
  try {
    const config = await publicConfig();
    ttlOptions.value = config.ttl_options;
    maxBytes.value = config.max_secret_bytes;
    maxFileBytes.value = config.max_file_bytes ?? 0;
    ttl.value = config.ttl_options.includes(config.default_ttl)
      ? config.default_ttl
      : (config.ttl_options[0] ?? 0);
    configReady.value = true;
  } catch {
    // Fail closed: without the server allowlist there is no valid TTL to send.
    configNote.value = "Could not load server settings. Refresh the page to try again.";
  }
});

async function submit() {
  // Synchronous reentry guard: a disabled button is patched asynchronously,
  // so a double-click or Enter-repeat could otherwise create two secrets.
  if (submitting.value) return;
  error.value = "";
  if (mode.value === "file" && !chosenFile.value) {
    error.value = "Choose a file to share.";
    return;
  }
  if (secret.value === "") {
    error.value = mode.value === "file" ? "Choose a file to share." : "Enter the secret you want to share.";
    return;
  }
  if (mode.value === "text" && bytes.value > maxBytes.value) {
    error.value = "The secret is too large. Use a shorter value.";
    return;
  }
  if (passphrase.value !== "" && new TextEncoder().encode(passphrase.value).length < 8) {
    error.value = "Use at least 8 bytes for the passphrase, or leave it empty.";
    return;
  }
  if (new TextEncoder().encode(passphrase.value).length > 256) {
    error.value = "The passphrase is too long (256 bytes maximum).";
    return;
  }
  if (mode.value === "file") {
    const nameBytes = new TextEncoder().encode(fileName.value).length;
    if (nameBytes < 1 || nameBytes > 255) {
      error.value = "Use a filename between 1 and 255 bytes.";
      return;
    }
  }

  submitting.value = true;
  try {
    result.value = await concealSecret({
      secret: secret.value,
      ttl: ttl.value,
      passphrase: passphrase.value || undefined,
      kind: mode.value,
      filename: mode.value === "file" ? fileName.value : undefined,
    });
    // Do not keep plaintext in component state after the request succeeds.
    secret.value = "";
    textDraft.value = "";
    fileName.value = "";
    passphrase.value = "";
    chosenFile.value = null;
    await nextTick();
    resultHeading.value?.focus();
  } catch (cause) {
    error.value = errorMessage(cause);
  } finally {
    submitting.value = false;
  }
}

function reset() {
  result.value = null;
  error.value = "";
  chosenFile.value = null;
  fileName.value = "";
  textDraft.value = "";
  secret.value = "";
  passphrase.value = "";
  nextTick(() => secretInput.value?.focus());
}
</script>

<template>
  <div class="ots-enter">
    <div v-if="!result" class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_19rem] lg:gap-12">
      <section class="ots-panel overflow-hidden" aria-labelledby="compose-heading">
        <div class="flex items-center gap-3 border-b border-border px-6 py-4 sm:px-8">
          <span class="ots-eyebrow shrink-0 whitespace-nowrap">01 / Compose</span>
          <span class="ots-rule flex-1" aria-hidden="true" />
          <span class="text-xs text-muted">Nothing is sent until you create the link</span>
        </div>

        <div class="space-y-7 px-6 py-7 sm:px-8 sm:py-9">
          <div class="space-y-3">
            <h1 id="compose-heading" class="ots-title">
              Share a secret once
            </h1>
            <p class="max-w-xl leading-relaxed text-muted">
              Paste a password, key or private note. The recipient gets a link that works
              exactly once — then the server forgets it.
            </p>
          </div>

          <AppAlert v-if="configNote">{{ configNote }}</AppAlert>

          <form class="space-y-6" @submit.prevent="submit">
            <div class="space-y-3">
              <div class="flex gap-2" role="group" aria-label="What do you want to share?">
                <button
                  type="button"
                  :aria-pressed="mode === 'text'"
                  :class="[
                    'inline-flex min-h-11 items-center rounded-md px-4 py-2 text-sm font-semibold transition-colors',
                    mode === 'text' ? 'bg-accent text-on-accent' : 'ots-inset text-muted hover:text-text',
                  ]"
                  @click="setMode('text')"
                >
                  Text
                </button>
                <button
                  type="button"
                  :aria-pressed="mode === 'file'"
                  :class="[
                    'inline-flex min-h-11 items-center rounded-md px-4 py-2 text-sm font-semibold transition-colors',
                    mode === 'file' ? 'bg-accent text-on-accent' : 'ots-inset text-muted hover:text-text',
                  ]"
                  @click="setMode('file')"
                >
                  File
                </button>
              </div>

              <template v-if="mode === 'text'">
                <label for="secret" class="block text-sm font-semibold">Secret</label>
                <textarea
                  id="secret"
                  ref="secretInput"
                  v-model="secret"
                  rows="8"
                  spellcheck="false"
                  autocomplete="off"
                  aria-describedby="secret-help"
                  class="ots-inset w-full resize-y p-3 font-mono text-sm text-text placeholder:text-muted"
                  placeholder="Paste the value you want to share…"
                />
              </template>
              <template v-else>
                <label for="file" class="block text-sm font-semibold">File</label>
                <input
                  id="file"
                  type="file"
                  class="ots-inset w-full p-3 text-sm text-text"
                  aria-describedby="secret-help"
                  @change="chooseFile"
                />
                <p v-if="readingFile" class="text-xs text-muted" role="status">Reading file…</p>
                <p v-if="chosenFile" class="text-xs text-muted">
                  {{ fileName }} · {{ sizeLabel(chosenFile.size) }} — encrypted before it is stored.
                </p>
              </template>

              <div id="secret-help" class="flex flex-wrap items-center justify-between gap-2 text-xs text-muted">
                <span>{{ mode === 'file' ? 'Files are private only until the link is opened.' : 'Never put secrets in the URL or in an email.' }}</span>
                <span>{{ payloadBytes }} / {{ limitBytes }} bytes</span>
              </div>
              <div class="h-1 overflow-hidden rounded-full bg-border" aria-hidden="true">
                <div
                  class="h-full rounded-full transition-[width] duration-200"
                  :class="usageRaw > 100 ? 'bg-danger' : usageRaw > 90 ? 'bg-warning' : 'bg-accent'"
                  :style="{ width: `${usage}%` }"
                />
              </div>
            </div>

            <div class="grid gap-5 sm:grid-cols-2">
              <div class="space-y-2">
                <label for="ttl" class="block text-sm font-semibold">Expires after</label>
                <select
                  id="ttl"
                  v-model.number="ttl"
                  class="ots-inset w-full px-3 py-2.5 text-sm"
                >
                  <option v-for="option in ttlOptions" :key="option" :value="option">
                    {{ ttlLabel(option) }}
                  </option>
                </select>
                <p class="text-xs text-muted">The clock starts when the link is created.</p>
              </div>

              <div class="space-y-2">
                <label for="passphrase" class="block text-sm font-semibold">
                  Passphrase <span class="font-normal text-muted">(optional)</span>
                </label>
                <input
                  id="passphrase"
                  v-model="passphrase"
                  type="password"
                  autocomplete="new-password"
                  maxlength="256"
                  class="ots-inset w-full px-3 py-2.5 text-sm"
                  aria-describedby="passphrase-help"
                  placeholder="Leave empty for none"
                />
                <p id="passphrase-help" class="text-xs text-muted">
                  8 bytes minimum. Share it through a different channel.
                </p>
              </div>
            </div>

            <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

            <div class="flex flex-wrap items-center gap-4 pt-1">
              <AppButton type="submit" :loading="submitting" :disabled="!configReady">
                {{ submitting ? "Creating link…" : "Create the link" }}
              </AppButton>
              <span class="text-xs text-muted">No account needed on either end.</span>
            </div>
          </form>
        </div>
      </section>

      <aside class="space-y-5" aria-label="How OneShotLink works">
        <div class="ots-panel p-5">
          <p class="ots-eyebrow">The contract</p>
          <ol class="mt-4 space-y-4 text-sm">
            <li class="flex gap-3">
              <span class="font-mono text-xs text-accent">01</span>
              <span><strong class="text-text">Encrypted at rest.</strong> Redis holds ciphertext, never the plaintext you typed.</span>
            </li>
            <li class="flex gap-3">
              <span class="font-mono text-xs text-accent">02</span>
              <span><strong class="text-text">A preview cannot spend it.</strong> Opening the link in a chat client does not consume the secret; the recipient confirms reveal.</span>
            </li>
            <li class="flex gap-3">
              <span class="font-mono text-xs text-accent">03</span>
              <span><strong class="text-text">One view, then gone.</strong> The delete is atomic, so two simultaneous opens cannot both succeed.</span>
            </li>
          </ol>
        </div>

        <div class="ots-inset p-5 text-sm leading-relaxed text-muted">
          <p class="font-semibold text-text">What a passphrase does</p>
          <p class="mt-2">
            It is an extra access check. The server holds the encryption key, so this is not
            client-side encryption — say that out loud when you choose who gets the link.
          </p>
        </div>

        <p class="text-xs text-muted">
          Limits on this instance: {{ sizeLabel(maxBytes) }} of text, {{ sizeLabel(maxFileBytes) }} per file.
        </p>
      </aside>
    </div>

    <section v-else class="ots-panel ots-enter mx-auto max-w-3xl overflow-hidden" aria-labelledby="result-heading">
      <div class="flex items-center gap-3 border-b border-border px-6 py-4 sm:px-8">
        <span class="ots-eyebrow">02 / Send</span>
        <span class="ots-rule flex-1" aria-hidden="true" />
        <span class="text-xs text-muted">Ready to share</span>
      </div>
      <div class="space-y-7 px-6 py-8 sm:px-8 sm:py-10">
        <div class="space-y-3">
          <h1 id="result-heading" ref="resultHeading" tabindex="-1" class="ots-title-compact">
            Your link, ready to send
          </h1>
          <p class="text-muted">
            Send this link to the recipient. It works once and then stops working.
          </p>
        </div>

        <div class="ots-inset space-y-4 p-5">
          <p class="break-all font-mono text-sm text-text">{{ link }}</p>
          <CopyButton :text="link" label="Copy link" />
        </div>

        <div class="grid gap-3 sm:grid-cols-2">
          <AppAlert v-if="result.receipt.kind === 'file'" tone="success">
            The file is stored encrypted. Deleted after one download, or after
            {{ ttlLabel(result.receipt.secret_ttl) }}.
          </AppAlert>
          <AppAlert v-else tone="success">
            Stored encrypted. Deleted after one view, or after {{ ttlLabel(result.receipt.secret_ttl) }}.
          </AppAlert>
          <AppAlert v-if="result.receipt.passphrase_required">
            This secret also needs the passphrase you set. Send it through a different channel.
          </AppAlert>
        </div>

        <AppButton variant="secondary" @click="reset">Create another secret</AppButton>
      </div>
    </section>
  </div>
</template>
