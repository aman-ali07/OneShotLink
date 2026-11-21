import { beforeEach, describe, expect, it, vi } from "vitest";
import { reactive } from "vue";
import { flushPromises, mount } from "@vue/test-utils";

const route = reactive<{ params: { key: string } }>({ params: { key: "first-key" } });
const peekSecret = vi.fn();
const revealSecret = vi.fn();

vi.mock("vue-router", () => ({ useRoute: () => route, useRouter: () => ({ push: vi.fn() }) }));
vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return {
    ...actual,
    peekSecret: (...args: unknown[]) => peekSecret(...args),
    revealSecret: (...args: unknown[]) => revealSecret(...args),
  };
});

const preview = (passphraseRequired: boolean) => ({
  passphrase_required: passphraseRequired,
  metadata: { kind: "text", filename: null, created_at: null, ttl: 1800 },
});

async function render() {
  const { default: RevealView } = await import("./RevealView.vue");
  const wrapper = mount(RevealView, { global: { stubs: { RouterLink: true } } });
  await flushPromises();
  return wrapper;
}

describe("RevealView route reuse", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    route.params.key = "first-key";
    peekSecret.mockImplementation((key: string) =>
      Promise.resolve(preview(key === "second-key")),
    );
  });

  it("peeks the new key again when the router reuses this view", async () => {
    const wrapper = await render();
    expect(peekSecret).toHaveBeenCalledWith("first-key", expect.any(AbortSignal));
    expect(wrapper.find("#reveal-passphrase").exists()).toBe(false);

    route.params.key = "second-key";
    await flushPromises();

    expect(peekSecret).toHaveBeenCalledWith("second-key", expect.any(AbortSignal));
    expect(wrapper.find("#reveal-passphrase").exists()).toBe(true);
  });
});
