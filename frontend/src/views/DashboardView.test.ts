import { beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";

const createRequest = vi.fn();

vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return {
    ...actual,
    getAccount: vi.fn().mockResolvedValue({
      customer: { id: "cust_qa", email: "qa@example.com", role: "customer" },
    }),
    listReceipts: vi.fn().mockResolvedValue({ receipts: [] }),
    listRequests: vi.fn().mockResolvedValue({ requests: [] }),
    listWebhooks: vi.fn().mockResolvedValue({ webhooks: [] }),
    createRequest: (...args: unknown[]) => createRequest(...args),
  };
});
vi.mock("@/lib/authMode", () => ({ accountsEnabled: vi.fn().mockResolvedValue(true) }));
vi.mock("@/lib/config", () => ({
  ttlOptions: vi.fn().mockResolvedValue([300, 600]),
  defaultTtl: vi.fn().mockResolvedValue(300),
}));
vi.mock("vue-router", async (importOriginal) => {
  const actual = await importOriginal<typeof import("vue-router")>();
  return { ...actual, useRouter: () => ({ push: vi.fn() }) };
});

async function render() {
  const { default: DashboardView } = await import("./DashboardView.vue");
  const wrapper = mount(DashboardView, {
    global: { stubs: { RouterLink: true, RouterView: true } },
  });
  await flushPromises();
  return wrapper;
}

describe("DashboardView request-link copy", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    createRequest.mockResolvedValue({
      request_key: "qa-key",
      metadata: { label: "QA", ttl: 300 },
      links: { request: "/request/qa-key" },
    });
  });

  it("does not claim success when both clipboard paths fail", async () => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error("denied")) },
    });
    document.execCommand = vi.fn().mockReturnValue(false) as typeof document.execCommand;

    const wrapper = await render();
    await wrapper.find("#request-label").setValue("QA request");
    const form = wrapper.findAll("form").find((candidate) => candidate.find("#request-label").exists());
    expect(form).toBeDefined();
    await form!.trigger("submit");
    await flushPromises();

    expect(wrapper.text()).not.toContain("Link created and copied");
    expect(wrapper.get('[role="alert"]').text()).toContain("Copy failed");
  });

  it("reports the link as copied only when the clipboard accepts it", async () => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
    });

    const wrapper = await render();
    await wrapper.find("#request-label").setValue("QA request");
    const form = wrapper.findAll("form").find((candidate) => candidate.find("#request-label").exists());
    await form!.trigger("submit");
    await flushPromises();

    expect(wrapper.get('[role="status"]').text()).toContain("Link created and copied");
  });
});
