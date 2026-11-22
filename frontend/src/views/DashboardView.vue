<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { accountsEnabled } from "@/lib/authMode";
import { copyText } from "@/lib/clipboard";
import { defaultTtl, ttlOptions } from "@/lib/config";
import { dateTimeLabel, ttlLabel } from "@/lib/format";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import CopyButton from "@/components/CopyButton.vue";
import {
  ApiError,
  burnSecret,
  changePassword,
  createRequest,
  createWebhook,
  deleteWebhook,
  deleteAccount,
  errorMessage,
  type Delivery,
  getAccount,
  listReceipts,
  listRequests,
  listWebhookDeliveries,
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

const accountsOn = ref(true);
const customer = ref<Customer | null>(null);
const receipts = ref<Receipt[]>([]);
const requests = ref<RequestItem[]>([]);
const requestLabel = ref("");
// Both come from /api/v3/config in onMounted; never hardcode an operator's TTL allowlist.
const requestTtl = ref(86400);
const requestTtlOptions = ref<number[]>([]);
const creatingRequest = ref(false);
const requestError = ref("");
const requestNote = ref("");
const requestNoteTone = ref<"success" | "danger">("success");
const revealedRequest = ref<{ value: string; label: string } | null>(null);
const revealingKey = ref("");
const burningKey = ref("");
const receiptError = ref("");
const receiptNote = ref("");
const webhooks = ref<Webhook[]>([]);
const deliveries = ref<Record<string, Delivery[]>>({});
const loadingDeliveries = ref("");
const hookUrl = ref("");
const hookEvents = ref<string[]>(["secret.revealed"]);
const addingHook = ref(false);
const hookError = ref("");
const newSigningSecret = ref("");
const loading = ref(true);
const unauthenticated = ref(false);
// AUTH_MODE=full is deliberately unimplemented (501). It is permanent, so it
// gets an honest "unavailable" panel instead of a retry that can never work.
const unavailable = ref("");
const error = ref("");
const confirmHookId = ref("");
const confirmDelete = ref(false);
const actionError = ref("");
const actionNote = ref("");
const deliveryError = ref("");
const currentPassword = ref("");
const newPassword = ref("");
const changing = ref(false);
const deletePassword = ref("");
const deleting = ref(false);
const router = useRouter();
const activeCount = computed(() => receipts.value.length);
const protectedCount = computed(() => receipts.value.filter((r) => r.passphrase_required).length);

function formatDate(seconds?: number): string {
  return seconds ? dateTimeLabel(seconds) : "";
}

// A session can expire while the dashboard is open. Route every action's 401
// to a fresh sign-in instead of leaving a dead view with a raw error string.
function handleActionError(cause: unknown): string {
  if (cause instanceof ApiError && cause.status === 401 && cause.code === "unauthorized") {
    customer.value = null;
    unauthenticated.value = true;
    void router.push({ path: "/signin", query: { redirect: "/dashboard" } });
    return "";
  }
  return errorMessage(cause);
}

async function load() {
  loading.value = true;
  error.value = "";
  unavailable.value = "";
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
    // 401 = signed out; 403 = accounts disabled (every account route refuses).
    // Both must render the honest "accounts are off / sign in" panel, not a
    // generic retry screen.
    if (cause instanceof ApiError && cause.status === 501) {
      unavailable.value = "Accounts are not configured on this instance. Sharing still needs no account.";
    } else if (cause instanceof ApiError && (cause.status === 401 || cause.status === 403)) {
      unauthenticated.value = true;
    } else {
      error.value = errorMessage(cause);
    }
  } finally {
    loading.value = false;
  }
}

function requestLink(key: string): string {
  // Hash fragment keeps the request capability out of CDN access logs.
  return `${window.location.origin}/#/request/${encodeURIComponent(key)}`;
}

async function copyRequestLink(key: string): Promise<boolean> {
  return copyText(requestLink(key));
}

async function createIncomingRequest() {
  requestError.value = "";
  requestNote.value = "";
  requestNoteTone.value = "success";
  creatingRequest.value = true;
  try {
    const created = await createRequest(requestLabel.value, requestTtl.value);
    requestLabel.value = "";
    await load();
    const copied = await copyRequestLink(created.request_key);
    requestNoteTone.value = copied ? "success" : "danger";
    requestNote.value = copied
      ? "Link created and copied. Give it to the person who owes you a secret."
      : "Copy failed — link created. Use the Copy link button in the list below.";
  } catch (cause) {
    requestError.value = handleActionError(cause);
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
    requestError.value = handleActionError(cause);
  } finally {
    revealingKey.value = "";
  }
}

// The status field is the owner-side record of what happened to a link. It lets
// the dashboard show "already viewed"/"burned" instead of a meaningless row.
function receiptStatus(receipt: Receipt): string {
  return receipt.status ?? "new";
}

const TERMINAL_STATUSES = ["revealed", "burned"];

async function burnLink(receipt: Receipt) {
  if (!window.confirm("Destroy this secret now? The link stops working immediately and cannot be undone.")) {
    return;
  }
  burningKey.value = receipt.identifier;
  receiptError.value = "";
  receiptNote.value = "";
  try {
    await burnSecret(receipt.identifier);
    receiptNote.value = "Secret destroyed. The link no longer works.";
    await load();
  } catch (cause) {
    receiptError.value = handleActionError(cause);
  } finally {
    burningKey.value = "";
  }
}

async function toggleDeliveries(id: string) {
  if (deliveries.value[id]) {
    const next = { ...deliveries.value };
    delete next[id];
    deliveries.value = next;
    return;
  }
  deliveryError.value = "";
  loadingDeliveries.value = id;
  try {
    const result = await listWebhookDeliveries(id);
    deliveries.value = { ...deliveries.value, [id]: result.deliveries };
  } catch (cause) {
    deliveryError.value = handleActionError(cause);
  } finally {
    loadingDeliveries.value = "";
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
    hookError.value = handleActionError(cause);
  } finally {
    addingHook.value = false;
  }
}

async function removeHook(id: string) {
  // Two-step confirmation: removing a webhook discards its signing secret.
  if (confirmHookId.value !== id) {
    confirmHookId.value = id;
    hookError.value = "";
    return;
  }
  confirmHookId.value = "";
  hookError.value = "";
  try {
    await deleteWebhook(id);
    await load();
  } catch (cause) {
    hookError.value = handleActionError(cause);
  }
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
    actionError.value = handleActionError(cause);
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
  if (!confirmDelete.value) {
    confirmDelete.value = true;
    actionNote.value = "Press again to permanently delete this account, its sessions and its receipts.";
    return;
  }

  deleting.value = true;
  try {
    await deleteAccount({ password: deletePassword.value });
    await router.push("/");
  } catch (cause) {
    actionError.value = handleActionError(cause);
  } finally {
    deleting.value = false;
    deletePassword.value = "";
  }
}

onMounted(async () => {
  accountsOn.value = await accountsEnabled();
  try {
    const [options, configuredDefault] = await Promise.all([ttlOptions(), defaultTtl()]);
    requestTtlOptions.value = options;
    requestTtl.value = options.includes(configuredDefault) ? configuredDefault : (options[0] ?? 86400);
  } catch {
    // Keep the documented defaults when /config is unavailable.
  }
  await load();
});

onBeforeUnmount(() => {
  // Revealed answers, signing secrets and passwords must not outlive the view.
  revealedRequest.value = null;
  newSigningSecret.value = "";
  currentPassword.value = "";
  newPassword.value = "";
  deletePassword.value = "";
  confirmDelete.value = false;
  confirmHookId.value = "";
});
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
      <h1 class="ots-title-compact">Your account</h1>
      <AppAlert v-if="accountsOn">Sign in to see the secret links you have created.</AppAlert>
      <AppAlert v-else tone="success">
        Accounts are off on this instance. Sharing needs no account — create a link instead.
      </AppAlert>
      <div v-if="accountsOn" class="flex flex-wrap gap-3">
        <AppButton @click="router.push({ path: '/signin', query: { redirect: '/dashboard' } })">
          Sign in
        </AppButton>
        <AppButton variant="secondary" @click="router.push('/signup')">Create account</AppButton>
      </div>
      <AppButton v-else @click="router.push('/')">Create a link</AppButton>
    </section>

    <template v-else-if="customer">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-2">
          <p class="ots-eyebrow">Account / Overview</p>
          <h1 class="ots-title">Your account</h1>
          <p class="text-muted">Signed in as {{ customer.email }}</p>
        </div>
        <AppButton variant="secondary" @click="logout">Sign out</AppButton>
      </div>

      <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

      <div class="grid gap-3 sm:grid-cols-3">
        <div class="ots-panel p-5">
          <p class="text-xs text-muted">Links created</p>
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

          <AppAlert v-if="receiptError" tone="danger">{{ receiptError }}</AppAlert>
          <AppAlert v-if="receiptNote" tone="success">{{ receiptNote }}</AppAlert>

        <p v-if="receipts.length === 0" class="rounded-md border border-border bg-surface p-4 text-sm text-muted">
          No links yet. <RouterLink to="/" class="font-semibold text-accent hover:underline">Create one from the home page</RouterLink>.
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
              <p class="text-xs font-semibold" :class="TERMINAL_STATUSES.includes(receiptStatus(receipt)) ? 'text-muted' : 'text-accent'">
                {{
                  receiptStatus(receipt) === 'revealed' ? 'Already viewed — destroyed' :
                  receiptStatus(receipt) === 'burned' ? 'Destroyed by you' :
                  receiptStatus(receipt) === 'previewed' ? 'Link opened, not yet viewed' : 'Waiting to be opened'
                }}
              </p>
            </div>
            <AppButton
              v-if="!TERMINAL_STATUSES.includes(receiptStatus(receipt))"
              type="button"
              variant="danger"
              :loading="burningKey === receipt.identifier"
              @click="burnLink(receipt)"
            >
              {{ burningKey === receipt.identifier ? 'Destroying…' : 'Destroy now' }}
            </AppButton>
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
                required
                class="ots-inset w-full px-3 py-2.5 text-sm"
                placeholder="e.g. Your API key"
              />
            </div>
            <div class="space-y-2">
              <label for="request-ttl" class="block text-sm font-semibold">Expires</label>
              <select id="request-ttl" v-model.number="requestTtl" class="ots-inset px-3 py-2.5 text-sm">
                <option v-for="option in requestTtlOptions" :key="option" :value="option">
                  {{ ttlLabel(option) }}
                </option>
              </select>
            </div>
            <AppButton type="submit" :loading="creatingRequest">Create link</AppButton>
          </form>

          <AppAlert v-if="requestError" tone="danger">{{ requestError }}</AppAlert>
          <AppAlert v-if="requestNote" :tone="requestNoteTone">{{ requestNote }}</AppAlert>

          <div v-if="revealedRequest" class="ots-inset space-y-3 p-4" aria-live="polite">
            <p class="text-sm font-semibold">Secret for {{ revealedRequest.label }}</p>
            <pre class="max-h-48 overflow-auto whitespace-pre-wrap break-words font-mono text-sm">{{ revealedRequest.value }}</pre>
            <CopyButton :text="revealedRequest.value" label="Copy answer" />
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
                <CopyButton :text="requestLink(item.request_key)" label="Copy link" />
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
                <label v-for="event in WEBHOOK_EVENTS" :key="event" class="flex min-h-11 items-center gap-2 text-xs text-muted">
                  <input
                    type="checkbox"
                    class="h-5 w-5"
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
          <AppAlert v-if="deliveryError" tone="danger">{{ deliveryError }}</AppAlert>

          <div v-if="newSigningSecret" class="ots-inset space-y-3 p-4" aria-live="polite">
            <p class="text-sm font-semibold">Copy this signing secret now</p>
            <p class="break-all font-mono text-xs text-text">{{ newSigningSecret }}</p>
            <div class="flex gap-2">
              <CopyButton :text="newSigningSecret" label="Copy secret" />
              <AppButton type="button" variant="secondary" @click="newSigningSecret = ''">Done</AppButton>
            </div>
            <p class="text-xs text-muted">It is encrypted in Redis and is not shown again.</p>
          </div>

          <p v-if="webhooks.length === 0" class="ots-inset p-4 text-sm text-muted">
            No endpoints yet. Add one to receive lifecycle events.
          </p>
          <ul v-else class="divide-y divide-border rounded-md border border-border bg-surface">
            <li v-for="hook in webhooks" :key="hook.id" class="space-y-3 p-4">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="min-w-0 space-y-1">
                  <p class="break-all font-mono text-sm text-text">{{ hook.url }}</p>
                  <p class="text-xs text-muted">{{ hook.events.join(' · ') }}</p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <AppButton type="button" variant="secondary" :loading="loadingDeliveries === hook.id"
                             @click="toggleDeliveries(hook.id)">
                    {{ deliveries[hook.id] ? 'Hide deliveries' : 'View deliveries' }}
                  </AppButton>
                  <AppButton type="button" variant="danger" @click="removeHook(hook.id)">
                    {{ confirmHookId === hook.id ? "Confirm remove" : "Remove" }}
                  </AppButton>
                </div>
              </div>
              <div v-if="deliveries[hook.id]" class="ots-inset p-3" aria-live="polite">
                <p v-if="deliveries[hook.id]!.length === 0" class="text-xs text-muted">No deliveries yet.</p>
                <ul v-else class="divide-y divide-border">
                  <li v-for="delivery in deliveries[hook.id]" :key="delivery.id" class="flex flex-wrap justify-between gap-2 py-2 text-xs">
                    <span class="font-mono text-text">{{ delivery.event }}</span>
                    <span class="text-muted">{{ delivery.status }} · {{ delivery.attempts }} attempt(s) ·
                      {{ delivery.response_code ?? '—' }} · {{ dateTimeLabel(delivery.created_at) }}</span>
                  </li>
                </ul>
              </div>
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
            {{ deleting ? "Deleting…" : confirmDelete ? "Confirm deletion" : "Delete my account" }}
          </AppButton>
        </form>
      </section>
      </div>
    </template>

    <section v-else-if="unavailable" class="ots-panel mx-auto max-w-md space-y-5 p-8">
      <p class="ots-eyebrow">Account</p>
      <h1 class="ots-title-compact">Accounts unavailable</h1>
      <AppAlert tone="danger">{{ unavailable }}</AppAlert>
      <AppButton variant="secondary" @click="router.push('/')">Share a secret instead</AppButton>
    </section>

    <section v-else class="ots-panel mx-auto max-w-md space-y-5 p-8">
      <p class="ots-eyebrow">Account</p>
      <h1 class="ots-title-compact">Your account</h1>
      <AppAlert tone="danger">
        {{ error || "Your account could not be loaded. Try again." }}
      </AppAlert>
      <AppButton @click="load()">Try again</AppButton>
    </section>
  </div>
</template>
