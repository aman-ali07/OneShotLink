<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import CopyButton from "@/components/CopyButton.vue";
import {
  concealSecret,
  errorMessage,
  getConfig,
  type ConcealResponse,
} from "@/lib/api";

const secret = ref("");
const ttl = ref(86400);
const passphrase = ref("");
const ttlOptions = ref<number[]>([1800, 43200, 86400, 259200]);
const maxBytes = ref(1024 * 1024);
const submitting = ref(false);
const error = ref("");
const configNote = ref("");
const result = ref<ConcealResponse | null>(null);
const resultHeading = ref<HTMLHeadingElement | null>(null);
const secretInput = ref<HTMLTextAreaElement | null>(null);

let controller: AbortController | undefined;

const bytes = computed(() => new TextEncoder().encode(secret.value).length);
const link = computed(() => {
  if (!result.value) return "";
  return new URL(result.value.links.secret, window.location.origin).toString();
});

function ttlLabel(seconds: number): string {
  if (seconds < 3600) return `${Math.round(seconds / 60)} minutes`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} hours`;
  return `${Math.round(seconds / 86400)} day${seconds >= 172800 ? "s" : ""}`;
}

onMounted(async () => {
  controller = new AbortController();
  try {
    const config = await getConfig(controller.signal);
    ttlOptions.value = config.ttl_options;
    maxBytes.value = config.max_secret_bytes;
    ttl.value = config.ttl_options.includes(config.default_ttl)
      ? config.default_ttl
      : (config.ttl_options[0] ?? 86400);
  } catch {
    configNote.value = "Could not load server settings. Default expiry options are shown.";
  }
});

onBeforeUnmount(() => controller?.abort());

async function submit() {
  error.value = "";
  if (secret.value === "") {
    error.value = "Enter the secret you want to share.";
    return;
  }
  if (bytes.value > maxBytes.value) {
    error.value = "The secret is too large. Use a shorter value.";
    return;
  }
  if (passphrase.value !== "" && new TextEncoder().encode(passphrase.value).length < 8) {
    error.value = "Use at least 8 characters for the passphrase, or leave it empty.";
    return;
  }

  submitting.value = true;
  try {
    result.value = await concealSecret({
      secret: secret.value,
      ttl: ttl.value,
      passphrase: passphrase.value || undefined,
    });
    // Do not keep plaintext in component state after the request succeeds.
    secret.value = "";
    passphrase.value = "";
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
  nextTick(() => secretInput.value?.focus());
}
</script>

<template>
  <div class="space-y-8">
    <section v-if="!result" class="space-y-6">
      <div class="space-y-2">
        <h1 class="text-3xl font-bold tracking-tight">Share a secret once</h1>
        <p class="text-muted">
          The recipient opens the link once. After that the secret is gone from the server.
        </p>
      </div>

      <AppAlert v-if="configNote">{{ configNote }}</AppAlert>

      <form class="space-y-6" @submit.prevent="submit">
        <div class="space-y-2">
          <label for="secret" class="block text-sm font-semibold">Secret</label>
          <textarea
            id="secret"
            ref="secretInput"
            v-model="secret"
            rows="8"
            spellcheck="false"
            autocomplete="off"
            aria-describedby="secret-help"
            class="w-full resize-y rounded-md border border-border-input bg-surface p-3 font-mono text-sm text-text"
          />
          <div id="secret-help" class="flex justify-between gap-4 text-xs text-muted">
            <span>Never put secrets in the URL or in an email.</span>
            <span>{{ bytes }} / {{ maxBytes }} bytes</span>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-2">
            <label for="ttl" class="block text-sm font-semibold">Expires after</label>
            <select
              id="ttl"
              v-model.number="ttl"
              class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
            >
              <option v-for="option in ttlOptions" :key="option" :value="option">
                {{ ttlLabel(option) }}
              </option>
            </select>
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
              minlength="8"
              maxlength="256"
              class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
              aria-describedby="passphrase-help"
            />
            <p id="passphrase-help" class="text-xs text-muted">
              8 characters minimum, or leave it empty. Share it separately from the link.
            </p>
          </div>
        </div>

        <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

        <AppButton type="submit" :loading="submitting">
          {{ submitting ? "Creating link…" : "Create the link" }}
        </AppButton>
      </form>
    </section>

    <section v-else class="space-y-6" aria-labelledby="result-heading">
      <div class="space-y-2">
        <h1 id="result-heading" ref="resultHeading" tabindex="-1" class="text-3xl font-bold tracking-tight">
          Your link, ready to send
        </h1>
        <p class="text-muted">
          Send this link to the recipient. It works once and then stops working.
        </p>
      </div>

      <div class="space-y-3 rounded-md border border-border bg-surface p-4 shadow-card">
        <p class="break-all font-mono text-sm">{{ link }}</p>
        <CopyButton :text="link" label="Copy link" />
      </div>

      <AppAlert v-if="result.receipt.passphrase_required">
        This secret also needs the passphrase you set. Send it through a different channel.
      </AppAlert>

      <AppAlert tone="success">
        Stored encrypted. Deleted after one view, or automatically after {{ ttlLabel(result.receipt.secret_ttl) }}.
      </AppAlert>

      <AppButton variant="secondary" @click="reset">Create another secret</AppButton>
    </section>
  </div>
</template>
