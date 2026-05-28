import Foundation

enum CSVParser {
    static func rows(from rawText: String) -> [CSVRow] {
        let records = parse(rawText)
        guard !records.isEmpty else {
            return []
        }

        return records.dropFirst().compactMap { columns in
            guard columns.count >= 4 else {
                return nil
            }

            return CSVRow(
                section: columns[0].trimmingCharacters(in: .whitespacesAndNewlines),
                subsection: columns[1].trimmingCharacters(in: .whitespacesAndNewlines),
                field: columns[2].trimmingCharacters(in: .whitespacesAndNewlines),
                value: columns[3].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func parse(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            switch character {
            case "\"":
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            case ",":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    currentField = ""
                }
            case "\n":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                }
            case "\r":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""

                    if index + 1 < characters.count, characters[index + 1] == "\n" {
                        index += 1
                    }
                }
            default:
                currentField.append(character)
            }

            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        if var firstField = rows.first?.first, firstField.hasPrefix("\u{FEFF}") {
            firstField.removeFirst()
            rows[0][0] = firstField
        }

        return rows
    }
}
