import Foundation

struct CSVRow: Equatable {
    var section: String
    var subsection: String
    var field: String
    var value: String
}

enum CSVService {
    static func parse(_ rawText: String) -> [CSVRow] {
        let records = parseRecords(rawText)
        guard !records.isEmpty else { return [] }

        return records.dropFirst().compactMap { columns in
            guard columns.count >= 4 else { return nil }
            return CSVRow(
                section: columns[0].trimmingCharacters(in: .whitespacesAndNewlines),
                subsection: columns[1].trimmingCharacters(in: .whitespacesAndNewlines),
                field: columns[2].trimmingCharacters(in: .whitespacesAndNewlines),
                value: columns[3].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func export(_ rows: [CSVRow]) -> String {
        let header = ["區塊", "子區塊", "欄位", "值"]
        let body = rows.map { [$0.section, $0.subsection, $0.field, $0.value] }
        return ([header] + body)
            .map { $0.map(escapeField).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func parseRecords(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
                index += 1
                continue
            }

            if character == ",", !inQuotes {
                currentRow.append(currentField)
                currentField = ""
                index += 1
                continue
            }

            if (character == "\n" || character == "\r"), !inQuotes {
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""

                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                index += 1
                continue
            }

            currentField.append(character)
            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        if rows.first?.first?.hasPrefix("\u{FEFF}") == true {
            rows[0][0].removeFirst()
        }

        return rows
    }

    private static func escapeField(_ value: String) -> String {
        let safeValue = neutralizeSpreadsheetFormula(value)
        if safeValue.range(of: #"[",\r\n]"#, options: .regularExpression) == nil {
            return safeValue
        }
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func neutralizeSpreadsheetFormula(_ value: String) -> String {
        if value.range(of: #"^[\s]*[=+\-@]"#, options: .regularExpression) != nil {
            return "'\(value)"
        }
        return value
    }
}
