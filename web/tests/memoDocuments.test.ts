import { describe, expect, test } from "vitest";
import {
  getCopyableRangeForSelection,
  normalizeCopyableRanges,
  splitMemoParagraphs,
  splitMemoParagraphsIntoSegments
} from "../src/memoDocuments";

describe("memo document helpers", () => {
  test("splits long memo content into display paragraphs", () => {
    expect(splitMemoParagraphs("第一段\n\n第二段\n還是第二段\n\n\n第三段")).toEqual([
      "第一段",
      "第二段\n還是第二段",
      "第三段"
    ]);
  });

  test("creates a copyable text range from a textarea selection", () => {
    const content = "第一段\n\n第二段可複製\n\n第三段";
    const start = content.indexOf("可複製");
    const end = start + "可複製".length;

    expect(getCopyableRangeForSelection(content, start, end)).toEqual({ start, end });
  });

  test("normalizes marked text ranges against the current content", () => {
    expect(normalizeCopyableRanges([
      { start: 8, end: 12 },
      { start: 2, end: 5 },
      { start: 4, end: 7 },
      { start: -1, end: 2 },
      { start: 30, end: 40 }
    ], "0123456789abcdef")).toEqual([
      { start: 2, end: 7 },
      { start: 8, end: 12 }
    ]);
  });

  test("splits memo paragraphs into copyable inline text segments", () => {
    const content = "它被用來保存尚未完成的工作、將筆記轉化為可運作的原型，或拆分出之後可以再回頭處理的探索性任務。這讓人重新接續。";
    const markedText = "拆分出之後可以再回頭處理的探索性任務";
    const start = content.indexOf(markedText);

    expect(splitMemoParagraphsIntoSegments(content, [{ start, end: start + markedText.length }])).toEqual([
      [
        { text: "它被用來保存尚未完成的工作、將筆記轉化為可運作的原型，或", copyable: false },
        { text: markedText, copyable: true },
        { text: "。這讓人重新接續。", copyable: false }
      ]
    ]);
  });
});
