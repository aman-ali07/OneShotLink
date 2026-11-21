import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import AppButton from "./AppButton.vue";

describe("AppButton", () => {
  it("renders the primary variant with a 44px hit area", () => {
    const wrapper = mount(AppButton, { slots: { default: "Create the link" } });
    expect(wrapper.classes()).toContain("bg-accent");
    expect(wrapper.classes()).toContain("text-on-accent");
    expect(wrapper.classes()).toContain("min-h-11");
    expect(wrapper.text()).toBe("Create the link");
  });

  it("disables and marks itself busy while loading", () => {
    const wrapper = mount(AppButton, {
      props: { loading: true },
      slots: { default: "Revealing…" },
    });
    const button = wrapper.get("button");
    expect(button.attributes("disabled")).toBeDefined();
    expect(button.attributes("aria-busy")).toBe("true");
  });

  it("uses semantic danger tokens and a real hover shade", () => {
    const wrapper = mount(AppButton, { props: { variant: "danger" } });
    expect(wrapper.classes()).toContain("bg-danger");
    expect(wrapper.classes()).toContain("text-on-danger");
    expect(wrapper.classes()).toContain("hover:bg-danger-hover");
    expect(wrapper.classes()).not.toContain("hover:opacity-90");
  });
});
