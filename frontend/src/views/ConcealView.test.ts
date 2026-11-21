import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";

const concealSecret = vi.fn();
const publicConfig = vi.fn();

vi.mock("@/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/api")>();
  return { ...actual, concealSecret: (...args: unknown[]) => concealSecret(...args) };
});
vi.mock("@/lib/config", () => ({ publicConfig: () => publicConfig() }));

function config() {
  return {
    ttl_options: [300, 600],
    default_ttl: 600,
    auth_mode: "disabled",
    ui_enabled: true,
    max_secret_bytes: 2048,
    max_file_bytes: 1024,
    version: "test",
  };
}

async function render() {
  const { default: ConcealView } = await import("./ConcealView.vue");
  const wrapper = mount(ConcealView);
  await flushPromises();
  return wrapper;
}

beforeEach(() => {
  // jsdom lacks execCommand; the real browser has it (see clipboard.ts).
  document.execCommand = vi.fn().mockReturnValue(true) as typeof document.execCommand;
  publicConfig.mockResolvedValue(config());
  concealSecret.mockResolvedValue({
    secret_key: "key123",
    receipt: { identifier: "key123", secret_ttl: 600, passphrase_required: false, status: "new" },
    links: { secret: "/secret/key123" },
  });
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("ConcealView", () => {
  it("uses the served TTL allowlist and byte caps, not hardcoded defaults", async () => {
    const wrapper = await render();

    const options = wrapper.findAll("#ttl option").map((option) => option.attributes("value"));
    expect(options).toEqual(["300", "600"]);
    expect((wrapper.find("#ttl").element as HTMLSelectElement).value).toBe("600");
    expect(wrapper.text()).toContain("2.0 KB");
  });

  it("clears a stashed plaintext draft after a successful create", async () => {
    const wrapper = await render();
    await wrapper.find("#secret").setValue("s3cr3t");
    await wrapper.findAll("button[type=button]")[1]!.trigger("click"); // File
    await wrapper.findAll("button[type=button]")[0]!.trigger("click"); // Text
    expect((wrapper.find("#secret").element as HTMLTextAreaElement).value).toBe("s3cr3t");

    await wrapper.find("form").trigger("submit");
    await flushPromises();
    expect(concealSecret).toHaveBeenCalledOnce();

    await wrapper.find("button").trigger("click"); // Create another secret is the footer button
    await flushPromises();
    const textButton = wrapper.findAll("button[type=button]")[0]!;
    await wrapper.findAll("button[type=button]")[1]!.trigger("click");
    await textButton.trigger("click");
    expect((wrapper.find("#secret").element as HTMLTextAreaElement).value).toBe("");
  });

  it("refuses an over-long passphrase before calling the API", async () => {
    const wrapper = await render();
    await wrapper.find("#secret").setValue("hello");
    await wrapper.find("#passphrase").setValue("😀".repeat(100)); // 400 bytes

    await wrapper.find("form").trigger("submit");
    await flushPromises();

    expect(concealSecret).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').text()).toContain("too long");
  });
});
