//
//  CSVParser.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

struct ParsedCSV {
    let headers: [String]
    let rows: [[String]]
}

enum CSVParserError: Error {
    case unreadableFile
    case empty
}

struct CSVParser {

    static func parse(url: URL) throws -> ParsedCSV {

        // 🔐 REQUIRED for fileImporter URLs
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)

        guard
            let content =
                String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1)
        else {
            throw CSVParserError.unreadableFile
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { throw CSVParserError.empty }

        let headerFields = splitCSVLine(lines[0])
        let headers = headerFields.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var outRows: [[String]] = []
        outRows.reserveCapacity(max(0, lines.count - 1))

        for line in lines.dropFirst() {
            let fields = splitCSVLine(line)
            let padded = pad(fields, to: headers.count)
            outRows.append(padded)
        }

        return ParsedCSV(headers: headers, rows: outRows)
    }

    private static func pad(_ arr: [String], to count: Int) -> [String] {
        if arr.count == count { return arr }
        if arr.count > count { return Array(arr.prefix(count)) }
        return arr + Array(repeating: "", count: count - arr.count)
    }

    // Handles commas + quoted fields
    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]

            if ch == "\"" {
                if inQuotes {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == ",", !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }

            i = line.index(after: i)
        }

        result.append(current)
        return result
    }
}
