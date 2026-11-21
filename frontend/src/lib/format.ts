// Pure display helpers shared by every view. Keeping one implementation fixes
// divergent formats (the dashboard used abbreviations while the other views
// spelled units out) and the old "100 B → 0 KB" bug.

export function ttlLabel(seconds: number): string {
  if (seconds < 3600) return `${Math.round(seconds / 60)} minutes`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} hours`;
  return `${Math.round(seconds / 86400)} day${seconds >= 172800 ? "s" : ""}`;
}

export function sizeLabel(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Medium date + short time, used for receipt and delivery timestamps.
export function dateTimeLabel(seconds: number): string {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" })
    .format(new Date(seconds * 1000));
}

export function formatTimestamp(seconds: number | null): string | null {
  if (!seconds) return null;
  // Explicit fields instead of dateStyle/timeStyle: the latter cannot be
  // combined with timeZoneName in every runtime (notably Node's ICU).
  return new Date(seconds * 1000).toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZoneName: "short",
  });
}
