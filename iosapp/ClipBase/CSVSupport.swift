import Foundation

struct CSVRow: Hashable {
    var section: String
    var subsection: String
    var field: String
    var value: String
}

enum CSVSupport {
    static func parse(_ text: String) throws -> [CSVRow] {
        var records = parseRecords(text)
            .filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        if records.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) == ["區塊", "子區塊", "欄位", "值"] {
            records.removeFirst()
        }

        return records.compactMap { record in
            guard record.count >= 4 else {
                return nil
            }
            return CSVRow(
                section: record[0].trimmingCharacters(in: .whitespacesAndNewlines),
                subsection: record[1].trimmingCharacters(in: .whitespacesAndNewlines),
                field: record[2].trimmingCharacters(in: .whitespacesAndNewlines),
                value: record[3]
            )
        }
    }

    static func export(sections: [ClipSection], itemsBySection: (String) -> [ClipItem]) -> String {
        var rows: [[String]] = [["區塊", "子區塊", "欄位", "值"]]

        for section in sections {
            for item in itemsBySection(section.id) {
                if let metadata = item.metadata, metadata.hasPrefix("建立時間：") {
                    rows.append([section.title, item.name, "訊息", item.content])
                    rows.append([section.title, item.name, "建立時間", String(metadata.dropFirst("建立時間：".count))])
                    continue
                }

                let parts = splitItemName(item.name)
                rows.append([section.title, parts.subsection, parts.field, item.content])
            }
        }

        return rows.map { row in
            row.map { escapeForCSV(neutralizeFormula($0)) }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private static func parseRecords(_ text: String) -> [[String]] {
        let characters = Array(text)
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isQuoted {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    if field.isEmpty {
                        isQuoted = true
                    } else {
                        field.append(character)
                    }
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    records.append(row)
                    row = []
                    field = ""
                case "\r":
                    if index + 1 < characters.count, characters[index + 1] == "\n" {
                        row.append(field)
                        records.append(row)
                        row = []
                        field = ""
                        index += 1
                    } else {
                        field.append(character)
                    }
                default:
                    field.append(character)
                }
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            records.append(row)
        }

        return records
    }

    private static func splitItemName(_ name: String) -> (subsection: String, field: String) {
        let separator = " / "
        guard let range = name.range(of: separator) else {
            return ("", name)
        }
        return (String(name[..<range.lowerBound]), String(name[range.upperBound...]))
    }

    private static func neutralizeFormula(_ value: String) -> String {
        if value.range(of: #"^\s*[=+\-@]"#, options: .regularExpression) != nil {
            return "'\(value)"
        }
        return value
    }

    private static func escapeForCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
