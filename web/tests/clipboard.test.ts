import { describe, expect, test, vi } from "vitest";
import { copyToClipboard } from "../src/clipboard";

describe("copyToClipboard", () => {
  test("falls back to a temporary textarea when navigator clipboard fails", async () => {
    const removed: unknown[] = [];
    const textarea = {
      value: "",
      setAttribute: vi.fn(),
      focus: vi.fn(),
      select: vi.fn(),
      remove: vi.fn(() => removed.push(textarea)),
      style: {}
    } as unknown as HTMLTextAreaElement;
    const appendChild = vi.fn();
    const execCommand = vi.fn(() => true);

    await copyToClipboard("標記文字", {
      navigator: {
        clipboard: {
          writeText: vi.fn().mockRejectedValue(new Error("clipboard denied"))
        }
      },
      document: {
        body: { appendChild },
        createElement: vi.fn(() => textarea),
        execCommand
      }
    });

    expect(textarea.value).toBe("標記文字");
    expect(appendChild).toHaveBeenCalledWith(textarea);
    expect(textarea.select).toHaveBeenCalled();
    expect(execCommand).toHaveBeenCalledWith("copy");
    expect(removed).toEqual([textarea]);
  });
});
