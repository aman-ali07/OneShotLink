<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import AppAlert from "@/components/AppAlert.vue";
import AppButton from "@/components/AppButton.vue";
import {
  ApiError,
  changePassword,
  deleteAccount,
  errorMessage,
  getAccount,
  listReceipts,
  signOut,
  type Customer,
  type Receipt,
} from "@/lib/api";

const customer = ref<Customer | null>(null);
const receipts = ref<Receipt[]>([]);
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
    const [account, list] = await Promise.all([getAccount(), listReceipts()]);
    customer.value = account.customer;
    receipts.value = list.receipts;
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
    <section v-if="loading" class="text-muted">Loading your account…</section>

    <section v-else-if="unauthenticated" class="mx-auto max-w-md space-y-4">
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
          <h1 class="text-3xl font-bold tracking-tight">Your account</h1>
          <p class="text-muted">Signed in as {{ customer.email }}</p>
        </div>
        <AppButton variant="secondary" @click="logout">Sign out</AppButton>
      </div>

      <AppAlert v-if="error" tone="danger">{{ error }}</AppAlert>

      <section class="space-y-4" aria-labelledby="receipts-heading">
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
      </section>

      <section class="max-w-md space-y-4" aria-labelledby="password-heading">
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

      <section class="max-w-md space-y-4" aria-labelledby="delete-heading">
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
    </template>
  </div>
</template>
