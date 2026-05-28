import { describe, expect, test } from "vitest";
import { exportCsv, parseCsv } from "../server/lib/csv.js";

describe("CSV import/export", () => {
  test("parses quoted commas, newlines, and escaped quotes", () => {
    const text = [
      "區塊,子區塊,欄位,值",
      "\"測試,帳號\",Admin,備註,\"line 1",
      "line 2 with \"\"quote\"\"\""
    ].join("\n");

    expect(parseCsv(text)).toEqual([
      {
        section: "測試,帳號",
        subsection: "Admin",
        field: "備註",
        value: "line 1\nline 2 with \"quote\""
      }
    ]);
  });

  test("exports rows using the same four-column format", () => {
    const csv = exportCsv([
      {
        section: "分類",
        subsection: "項目",
        field: "訊息",
        value: "hello, \"Clip\""
      }
    ]);

    expect(csv).toBe("區塊,子區塊,欄位,值\n分類,項目,訊息,\"hello, \"\"Clip\"\"\"");
  });

  test("neutralizes spreadsheet formulas when exporting", () => {
    const csv = exportCsv([
      {
        section: "=cmd",
        subsection: "+SUM(1,1)",
        field: "-10",
        value: "@HYPERLINK(\"https://evil.example\")"
      },
      {
        section: "安全分類",
        subsection: "",
        field: "備註",
        value: "  =IMPORTXML(\"https://evil.example\")"
      }
    ]);

    expect(csv).toBe([
      "區塊,子區塊,欄位,值",
      "'=cmd,\"'+SUM(1,1)\",'-10,\"'@HYPERLINK(\"\"https://evil.example\"\")\"",
      "安全分類,,備註,\"'  =IMPORTXML(\"\"https://evil.example\"\")\""
    ].join("\n"));
  });
});
