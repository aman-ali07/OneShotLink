<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import {
  ApiError,
  changePassword,
  createRequest,
  createWebhook,
  deleteWebhook,
  deleteAccount,
  errorMessage,
  getAccount,
  listReceipts,
  listRequests,
  listWebhooks,
  revealRequest,
  signOut,
  type Customer,
  type Receipt,
  type RequestItem,
  type Webhook,
} from "@/lib/api";

const WEBHOOK_EVENTS = [
  "secret.created",
  "secret.revealed",
  "request.created",
  "request.responded",
  "request.revealed",
] as const;

const customer = ref<Customer | null>(null);
const receipts = ref<Receipt[]>([]);
const requests = ref<RequestItem[]>([]);
const requestLabel = ref("");
const requestTtl = ref(86400);
const creatingRequest = ref(false);
const requestError = ref("");
const revealedRequest = ref<{ value: string; label: string } | null>(null);
const revealingKey = ref("");
const webhooks = ref<Webhook[]>([]);
const hookUrl = ref("");
const hookEvents = ref<string[]>(["secret.revealed"]);
const addingHook = ref(false);
const hookError = ref("");
const newSigningSecret = ref("");
const loading = ref(true);
const unauthenticated = ref(false);
const error = ref("");
const actionError = ref("");
const actionNote = ref("");
const currentPassword = ref("");
const newPassword = ref("");
const changing = ref(false);
const deletePassword = ref("");
const deleting = ref(false);
const router = useRouter();
const activeCount = computed(() => receipts.value.length);
const protectedCount = computed(() => receipts.value.filter((r) => r.passphrase_required).length);

function formatDate(seconds?: number): string {
  if (!seconds) return "";
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(
    new Date(seconds * 1000),
  );
}

function ttlLabel(seconds: number): string {
  if (seconds < 3600) return `${Math.round(seconds / 60)} min`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} h`;
  return `${Math.round(seconds / 86400)} d`;
}

async function load() {
  loading.value = true;
  error.value = "";
  try {
    const [account, list, incoming, hooks] = await Promise.all([
      getAccount(),
      listReceipts(),
      listRequests(),
      listWebhooks(),
    ]);
    customer.value = account.customer;
    receipts.value = list.receipts;
    requests.value = incoming.requests;
    webhooks.value = hooks.webhooks;
  } catch (cause) {
    if (cause instanceof ApiError && cause.status === 401) {
      unauthenticated.value = true;
    } else {
      error.value = errorMessage(cause);
    }
  } finally {
    loading.value = false;
  }
}

function requestLink(key: string): string {
  return new URL(`/request/${key}`, window.location.origin).toString();
}

function copyRequestLink(key: string) {
  void navigator.clipboard?.writeText(requestLink(key));
}

async function createIncomingRequest() {
  requestError.value = "";
  creatingRequest.value = true;
  try {
    const created = await createRequest(requestLabel.value, requestTtl.value);
    requestLabel.value = "";
    await load();
    copyRequestLink(created.request_key);
  } catch (cause) {
    requestError.value = errorMessage(cause);
  } finally {
    creatingRequest.value = false;
  }
}

async function openIncoming(item: RequestItem) {
  revealingKey.value = item.request_key;
  requestError.value = "";
  try {
    const result = await revealRequest(item.request_key);
    revealedRequest.value = { value: result.secret_value, label: item.label };
    await load();
  } catch (cause) {
    requestError.value = errorMessage(cause);
  } finally {
    revealingKey.value = "";
  }
}

async function addHook() {
  hookError.value = "";
  if (hookUrl.value.trim() === "" || hookEvents.value.length === 0) {
    hookError.value = "Enter an endpoint URL and choose at least one event.";
    return;
  }
  addingHook.value = true;
  try {
    const created = await createWebhook(hookUrl.value.trim(), hookEvents.value);
    newSigningSecret.value = created.signing_secret;
    hookUrl.value = "";
    await load();
  } catch (cause) {
    hookError.value = errorMessage(cause);
  } finally {
    addingHook.value = false;
  }
}

async function removeHook(id: string) {
  hookError.value = "";
  try {
    await deleteWebhook(id);
    await load();
  } catch (cause) {
    hookError.value = errorMessage(cause);
  }
}

function copyText(value: string) {
  void navigator.clipboard?.writeText(value);
}

function toggleHookEvent(event: string) {
  hookEvents.value = hookEvents.value.includes(event)
    ? hookEvents.value.filter((item) => item !== event)
    : [...hookEvents.value, event];
}

async function logout() {
  try {
    await signOut();
  } finally {
    await router.push("/");
  }
}

async function updatePassword() {
  actionError.value = "";
  actionNote.value = "";
  if (new TextEncoder().encode(newPassword.value).length < 12) {
    actionError.value = "Choose a password with at least 12 characters.";
    return;
  }

  changing.value = true;
  try {
    await changePassword({
      currentPassword: currentPassword.value,
      newPassword: newPassword.value,
    });
    currentPassword.value = "";
    newPassword.value = "";
    actionNote.value = "Password updated.";
  } catch (cause) {
    actionError.value = errorMessage(cause);
  } finally {
    changing.value = false;
  }
}

async function removeAccount() {
  actionError.value = "";
  actionNote.value = "";
  if (!deletePassword.value) {
    actionError.value = "Enter your password to delete the account.";
    return;
  }

  deleting.value = true;
  try {
    await deleteAccount({ password: deletePassword.value });
    await router.push("/");
  } catch (cause) {
    actionError.value = errorMessage(cause);
  } finally {
    deleting.value = false;
    deletePassword.value = "";
  }
}

onMounted(load);
</script>

<template>
  <div class="space-y-8">
    <section v-if="loading" class="ots-panel space-y-4 p-8" aria-live="polite" aria-busy="true">
      <p class="ots-eyebrow">Account</p>
      <div class="h-8 w-48 animate-pulse rounded bg-border" aria-hidden="true" />
      <div class="h-4 w-72 animate-pulse rounded bg-border" aria-hidden="true" />
      <div class="grid gap-3 pt-4 sm:grid-cols-3">
        <div v-for="n in 3" :key="n" class="h-20 animate-pulse rounded-md bg-border" aria-hidden="true" />
      </div>
      <span class="sr-only">Loading your account…</span>
    </section>

    <section v-else-if="unauthenticated" class="ots-panel mx-auto max-w-md space-y-5 p-8">
      <p class="ots-eyebrow">Account</p>
      <h1 class="text-3xl font-bold tracking-tight">Your account</h1>
      <AppAlert>Sign in to see the secret links you have created.</AppAlert>
      <div class="flex flex-wrap gap-3">
        <AppButton @click="router.push({ path: '/signin', query: { redirect: '/dashboard' } })">
          Sign in
        </AppButton>
        <AppButton variant="secondary" @click="router.push('/signup')">Create account</AppButton>
      </div>
    </section>

    <template v-else-if="customer">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-2">
          <p class="ots-eyebrow">Account / Overview</p>
          <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">Your account</h1>
          <p class="text-muted">Signed in as {{ customer.email }}</p>
        </div>
        <AppButton variant="secondary" @click="logout">Sign out</AppButton>
      </div>

      <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

      <div class="grid gap-3 sm:grid-cols-3">
        <div class="ots-panel p-5">
          <p class="text-xs text-muted">Active links</p>
          <p class="mt-2 text-2xl font-semibold text-text">{{ activeCount }}</p>
        </div>
        <div class="ots-panel p-5">
          <p class="text-xs text-muted">Passphrase protected</p>
          <p class="mt-2 text-2xl font-semibold text-text">{{ protectedCount }}</p>
        </div>
        <div class="ots-panel p-5">
          <p class="text-xs text-muted">Storage</p>
          <p class="mt-2 text-sm font-semibold text-text">Expires automatically</p>
        </div>
      </div>

      <section class="ots-panel overflow-hidden" aria-labelledby="receipts-heading">
        <div class="flex items-center gap-3 border-b border-border px-6 py-4">
          <span class="ots-eyebrow">Links</span>
          <span class="ots-rule flex-1" aria-hidden="true" />
          <span class="text-xs text-muted">Newest first</span>
        </div>
        <div class="space-y-4 px-6 py-6">
          <div class="space-y-1">
            <h2 id="receipts-heading" class="text-xl font-semibold">Recent links</h2>
            <p class="text-sm text-muted">
              Links you created. This list never contains the secret itself.
            </p>
          </div>

        <p v-if="receipts.length === 0" class="rounded-md border border-border bg-surface p-4 text-sm text-muted">
          No active links. Create one from the home page.
        </p>

        <ul v-else class="divide-y divide-border rounded-md border border-border bg-surface">
          <li v-for="receipt in receipts" :key="receipt.identifier" class="flex flex-wrap items-center justify-between gap-3 p-4">
            <div class="space-y-1">
              <RouterLink
                :to="receipt.secret_url ?? `/secret/${receipt.identifier}`"
                class="font-mono text-sm text-accent underline underline-offset-2"
              >
                {{ receipt.identifier }}
              </RouterLink>
              <p class="text-xs text-muted">
                Expires in {{ ttlLabel(receipt.secret_ttl) }}
                <template v-if="receipt.created_at">· Created {{ formatDate(receipt.created_at) }}</template>
                <template v-if="receipt.passphrase_required">· Passphrase required</template>
              </p>
            </div>
          </li>
        </ul>
        </div>
      </section>

      <section class="ots-panel overflow-hidden" aria-labelledby="requests-heading">
        <div class="flex items-center gap-3 border-b border-border px-6 py-4">
          <span class="ots-eyebrow">Incoming</span>
          <span class="ots-rule flex-1" aria-hidden="true" />
          <span class="text-xs text-muted">One answer per link</span>
        </div>
        <div class="space-y-5 px-6 py-6">
          <div class="space-y-1">
            <h2 id="requests-heading" class="text-xl font-semibold">Requests for a secret</h2>
            <p class="text-sm text-muted">
              Share a public link that lets someone send you one secret. You can open every answer once.
            </p>
          </div>

          <form class="grid items-end gap-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]" @submit.prevent="createIncomingRequest">
            <div class="space-y-2">
              <label for="request-label" class="block text-sm font-semibold">What do you need?</label>
              <input
                id="request-label"
                v-model="requestLabel"
                type="text"
                maxlength="120"
                class="ots-inset w-full px-3 py-2.5 text-sm"
                placeholder="e.g. Your API key"
              />
            </div>
            <div class="space-y-2">
              <label for="request-ttl" class="block text-sm font-semibold">Expires</label>
              <select id="request-ttl" v-model.number="requestTtl" class="ots-inset px-3 py-2.5 text-sm">
                <option v-for="option in [1800, 43200, 86400, 259200]" :key="option" :value="option">
                  {{ ttlLabel(option) }}
                </option>
              </select>
            </div>
            <AppButton type="submit" :loading="creatingRequest">Create link</AppButton>
          </form>

          <AppAlert v-if="requestError" tone="danger">{{ requestError }}</AppAlert>

          <div v-if="revealedRequest" class="ots-inset space-y-3 p-4" aria-live="polite">
            <p class="text-sm font-semibold">Secret for {{ revealedRequest.label }}</p>
            <pre class="max-h-48 overflow-auto whitespace-pre-wrap break-words font-mono text-sm">{{ revealedRequest.value }}</pre>
            <AppButton variant="secondary" type="button" @click="revealedRequest = null">Done</AppButton>
          </div>

          <p v-if="requests.length === 0" class="ots-inset p-4 text-sm text-muted">
            No request links yet. Create one above and send the link to the person who owes you a secret.
          </p>
          <ul v-else class="divide-y divide-border rounded-md border border-border bg-surface">
            <li v-for="item in requests" :key="item.request_key" class="flex flex-wrap items-center justify-between gap-3 p-4">
              <div class="space-y-1">
                <p class="font-semibold text-text">{{ item.label }}</p>
                <p class="text-xs text-muted">
                  {{ item.fulfilled ? "Answer received" : "Waiting for an answer" }} · Expires in {{ ttlLabel(item.ttl) }}
                </p>
              </div>
              <div class="flex flex-wrap gap-2">
                <AppButton variant="secondary" type="button" @click="copyRequestLink(item.request_key)">
                  Copy link
                </AppButton>
                <AppButton
                  v-if="item.fulfilled"
                  type="button"
                  :loading="revealingKey === item.request_key"
                  @click="openIncoming(item)"
                >
                  Reveal answer
                </AppButton>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section class="ots-panel overflow-hidden" aria-labelledby="webhooks-heading">
        <div class="flex items-center gap-3 border-b border-border px-6 py-4">
          <span class="ots-eyebrow">Developers</span>
          <span class="ots-rule flex-1" aria-hidden="true" />
          <span class="text-xs text-muted">Signed, idempotent delivery</span>
        </div>
        <div class="space-y-5 px-6 py-6">
          <div class="space-y-1">
            <h2 id="webhooks-heading" class="text-xl font-semibold">Webhooks</h2>
            <p class="text-sm text-muted">
              Receive metadata-only events. Payloads never contain secret values; each delivery
              carries a stable id and an HMAC-SHA256 signature.
            </p>
          </div>

          <form class="space-y-4" @submit.prevent="addHook">
            <div class="space-y-2">
              <label for="hook-url" class="block text-sm font-semibold">Endpoint URL</label>
              <input
                id="hook-url"
                v-model="hookUrl"
                type="url"
                class="ots-inset w-full px-3 py-2.5 text-sm"
                placeholder="https://hooks.example.com/ots"
              />
              <p class="text-xs text-muted">Public HTTPS endpoints only. Private addresses are refused.</p>
            </div>
            <fieldset class="space-y-2">
              <legend class="text-sm font-semibold">Events</legend>
              <div class="flex flex-wrap gap-3">
                <label v-for="event in WEBHOOK_EVENTS" :key="event" class="flex items-center gap-2 text-xs text-muted">
                  <input
                    type="checkbox"
                    :checked="hookEvents.includes(event)"
                    @change="toggleHookEvent(event)"
                  />
                  <span class="font-mono">{{ event }}</span>
                </label>
              </div>
            </fieldset>
            <AppButton type="submit" :loading="addingHook">Add endpoint</AppButton>
          </form>

          <AppAlert v-if="hookError" tone="danger">{{ hookError }}</AppAlert>

          <div v-if="newSigningSecret" class="ots-inset space-y-3 p-4" aria-live="polite">
            <p class="text-sm font-semibold">Copy this signing secret now</p>
            <p class="break-all font-mono text-xs text-text">{{ newSigningSecret }}</p>
            <div class="flex gap-2">
              <AppButton type="button" variant="secondary" @click="copyText(newSigningSecret)">Copy secret</AppButton>
              <AppButton type="button" variant="secondary" @click="newSigningSecret = ''">Done</AppButton>
            </div>
            <p class="text-xs text-muted">It is encrypted in Redis and is not shown again.</p>
          </div>

          <p v-if="webhooks.length === 0" class="ots-inset p-4 text-sm text-muted">
            No endpoints yet. Add one to receive lifecycle events.
          </p>
          <ul v-else class="divide-y divide-border rounded-md border border-border bg-surface">
            <li v-for="hook in webhooks" :key="hook.id" class="flex flex-wrap items-center justify-between gap-3 p-4">
              <div class="min-w-0 space-y-1">
                <p class="break-all font-mono text-sm text-text">{{ hook.url }}</p>
                <p class="text-xs text-muted">{{ hook.events.join(' · ') }}</p>
              </div>
              <AppButton type="button" variant="danger" @click="removeHook(hook.id)">Remove</AppButton>
            </li>
          </ul>
        </div>
      </section>

      <div class="grid gap-6 lg:grid-cols-2">
      <section class="ots-panel space-y-4 p-6" aria-labelledby="password-heading">
        <h2 id="password-heading" class="text-xl font-semibold">Change password</h2>
        <form class="space-y-3" @submit.prevent="updatePassword">
          <div class="space-y-2">
            <label for="current-password" class="block text-sm font-semibold">Current password</label>
            <input
              id="current-password"
              v-model="currentPassword"
              type="password"
              autocomplete="current-password"
              required
              class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
            />
          </div>
          <div class="space-y-2">
            <label for="new-password" class="block text-sm font-semibold">New password</label>
            <input
              id="new-password"
              v-model="newPassword"
              type="password"
              autocomplete="new-password"
              minlength="12"
              maxlength="256"
              required
              class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
            />
          </div>
          <AppAlert v-if="actionError" tone="danger">{{ actionError }}</AppAlert>
          <AppAlert v-if="actionNote" tone="success">{{ actionNote }}</AppAlert>
          <AppButton type="submit" :loading="changing">
            {{ changing ? "Updating…" : "Update password" }}
          </AppButton>
        </form>
      </section>

      <section class="ots-panel space-y-4 p-6" aria-labelledby="delete-heading">
        <h2 id="delete-heading" class="text-xl font-semibold">Delete account</h2>
        <p class="text-sm text-muted">
          This removes your account, its sessions and your list of links. Secrets that have not
          expired yet stay available to whoever holds the link until they expire.
        </p>
        <form class="space-y-3" @submit.prevent="removeAccount">
          <div class="space-y-2">
            <label for="delete-password" class="block text-sm font-semibold">Password</label>
            <input
              id="delete-password"
              v-model="deletePassword"
              type="password"
              autocomplete="current-password"
              required
              class="w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm"
            />
          </div>
          <AppButton type="submit" variant="danger" :loading="deleting">
            {{ deleting ? "Deleting…" : "Delete my account" }}
          </AppButton>
        </form>
      </section>
      </div>
    </template>
  </div>
</template>
