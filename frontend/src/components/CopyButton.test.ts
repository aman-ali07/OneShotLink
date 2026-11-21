import { beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import CopyButton from "./CopyButton.vue";

describe("CopyButton", () => {
  beforeEach(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
    });
  });

  it("announces success through a role=status region", async () => {
    const wrapper = mount(CopyButton, { props: { text: "value", label: "Copy secret" } });
    await wrapper.get("button").trigger("click");
    await flushPromises();
    expect(wrapper.get("button").text()).toBe("Copied");
    expect(wrapper.get('[role="status"]').text()).toContain("Copied to clipboard");
  });

  it("falls back to execCommand when the Clipboard API is unavailable", async () => {
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined });
    const execCommand = vi.fn().mockReturnValue(true);
    Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand });

    const wrapper = mount(CopyButton, { props: { text: "value" } });
    await wrapper.get("button").trigger("click");
    await flushPromises();

    expect(execCommand).toHaveBeenCalledWith("copy");
    expect(wrapper.get('[role="status"]').text()).toContain("Copied to clipboard");
  });

  it("reports failure without clearing the source text", async () => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error("denied")) },
    });
    const execCommand = vi.fn().mockReturnValue(false);
    Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand });

    const wrapper = mount(CopyButton, { props: { text: "value" } });
    await wrapper.get("button").trigger("click");
    await flushPromises();

    expect(wrapper.get('[role="status"]').text()).toContain("Copy failed");
  });
});
