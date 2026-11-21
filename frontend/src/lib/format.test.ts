import { describe, expect, it } from "vitest";
import { dateTimeLabel, formatTimestamp, sizeLabel, ttlLabel } from "./format";

describe("display formatters", () => {
  it("spells TTLs in the unit that matches the duration", () => {
    expect(ttlLabel(1800)).toBe("30 minutes");
    expect(ttlLabel(7200)).toBe("2 hours");
    expect(ttlLabel(86400)).toBe("1 day");
    expect(ttlLabel(172800)).toBe("2 days");
  });

  it("never calls a byte value zero kilobytes", () => {
    expect(sizeLabel(100)).toBe("100 B");
    expect(sizeLabel(1024)).toBe("1.0 KB");
    expect(sizeLabel(1024 * 1024)).toBe("1.0 MB");
  });

  it("formats timestamps without fabricating a date for absent values", () => {
    const epoch = 1_577_934_240; // 2020-01-02T03:04:00Z
    expect(formatTimestamp(null)).toBeNull();
    expect(formatTimestamp(0)).toBeNull();
    expect(formatTimestamp(epoch)).toContain("2020");
    expect(dateTimeLabel(epoch)).toContain("2020");
  });
});
