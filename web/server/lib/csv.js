export function parseCsv(rawText) {
  const records = parseRecords(rawText);
  if (records.length === 0) {
    return [];
  }

  return records.slice(1).flatMap((columns) => {
    if (columns.length < 4) {
      return [];
    }

    return [
      {
        section: columns[0].trim(),
        subsection: columns[1].trim(),
        field: columns[2].trim(),
        value: columns[3].trim()
      }
    ];
  });
}

export function exportCsv(rows) {
  const header = ["區塊", "子區塊", "欄位", "值"];
  return [header, ...rows].map((row) => {
    const values = Array.isArray(row)
      ? row
      : [row.section, row.subsection, row.field, row.value];

    return values.map(escapeField).join(",");
  }).join("\n");
}

function parseRecords(text) {
  const characters = Array.from(text);
  const rows = [];
  let currentRow = [];
  let currentField = "";
  let inQuotes = false;

  for (let index = 0; index < characters.length; index += 1) {
    const character = characters[index];

    if (character === "\"") {
      if (inQuotes && characters[index + 1] === "\"") {
        currentField += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (character === "," && !inQuotes) {
      currentRow.push(currentField);
      currentField = "";
      continue;
    }

    if ((character === "\n" || character === "\r") && !inQuotes) {
      currentRow.push(currentField);
      rows.push(currentRow);
      currentRow = [];
      currentField = "";

      if (character === "\r" && characters[index + 1] === "\n") {
        index += 1;
      }
      continue;
    }

    currentField += character;
  }

  if (currentField.length > 0 || currentRow.length > 0) {
    currentRow.push(currentField);
    rows.push(currentRow);
  }

  if (rows[0]?.[0]?.startsWith("\uFEFF")) {
    rows[0][0] = rows[0][0].slice(1);
  }

  return rows;
}

function escapeField(value) {
  const stringValue = neutralizeSpreadsheetFormula(String(value ?? ""));
  if (!/[",\r\n]/.test(stringValue)) {
    return stringValue;
  }

  return `"${stringValue.replaceAll("\"", "\"\"")}"`;
}

function neutralizeSpreadsheetFormula(value) {
  return /^[\s]*[=+\-@]/.test(value) ? `'${value}` : value;
}
