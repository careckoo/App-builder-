import Foundation
import Compression

/// Turns a statement file into rows of cells: CSV / TSV text, or an Excel .xlsx workbook (first sheet).
/// Everything is read on the phone. An .xlsx is a ZIP of XML files, read here without any library.
public enum SpreadsheetFiles {
    public enum ReadError: Error, Equatable { case notAWorkbook, noSheet, unreadableText }

    // MARK: Text

    /// UTF-8 (with or without BOM), UTF-16, or Windows Arabic (older bank exports).
    public static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        let arabic = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: arabic)) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    /// CSV with quotes ("a, b" and "" for a quote). The separator (, ; tab |) is guessed from the first lines.
    public static func csv(_ text: String) -> [[String]] {
        let sep = guessSeparator(text)
        var rows: [[String]] = [], row: [String] = [], cell = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? { if let p = pending { pending = nil; return p }; return chars.next() }
        while let ch = next() {
            if quoted {
                if ch == "\"" {
                    if let n = chars.next() {
                        if n == "\"" { cell.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else { cell.append(ch) }
                continue
            }
            switch ch {
            case "\"" where cell.trimmingCharacters(in: .whitespaces).isEmpty: cell = ""; quoted = true
            case sep: row.append(cell); cell = ""
            case "\n", "\r\n", "\r":
                row.append(cell); cell = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            default: cell.append(ch)
            }
        }
        row.append(cell)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    static func guessSeparator(_ text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(15)
        var best: (Character, Int) = (",", -1)
        for c in [",", ";", "\t", "|"] as [Character] {
            // The separator that splits most lines into the same, largest number of cells.
            let counts = lines.map { line -> Int in
                var inQ = false, n = 0
                for ch in line { if ch == "\"" { inQ.toggle() } else if ch == c, !inQ { n += 1 } }
                return n
            }
            let common = Dictionary(grouping: counts.filter { $0 > 0 }, by: { $0 }).max { $0.value.count < $1.value.count }
            let score = (common?.value.count ?? 0) * 10 + (common?.key ?? 0)
            if score > best.1 { best = (c, score) }
        }
        return best.0
    }

    // MARK: Excel

    /// The first worksheet of an .xlsx as rows of text. Numbers stay as written in the file ("45.5",
    /// "45567" for a date stored as an Excel day number); the statement reader understands both.
    public static func xlsx(_ data: Data) throws -> [[String]] {
        let zip = try ZipArchive(data)
        let shared = zip.file("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let sheetPath = firstSheetPath(zip) ?? zip.names.filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }.sorted().first
        guard let path = sheetPath, let sheet = zip.file(path) else { throw ReadError.noSheet }
        return SheetParser.parse(sheet, shared: shared)
    }

    /// workbook.xml names the sheets in order; its relationships file says which XML file each one is.
    static func firstSheetPath(_ zip: ZipArchive) -> String? {
        guard let wb = zip.file("xl/workbook.xml").flatMap({ String(data: $0, encoding: .utf8) }),
              let rels = zip.file("xl/_rels/workbook.xml.rels").flatMap({ String(data: $0, encoding: .utf8) }),
              let sheet = wb.range(of: #"<(?:\w+:)?sheet\b[^>]*>"#, options: .regularExpression).map({ String(wb[$0]) }),
              let rid = capture(#"r:id="([^"]+)""#, sheet) else { return nil }
        guard let rel = rels.components(separatedBy: "<Relationship").first(where: { $0.contains("Id=\"\(rid)\"") }),
              var target = capture(#"Target="([^"]+)""#, rel) else { return nil }
        if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
        return target
    }

    static func capture(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

// MARK: - ZIP

/// Reads the files of a ZIP archive (stored or deflated), which is what an .xlsx is.
struct ZipArchive {
    struct Entry { let method: UInt16; let compressed: Int; let size: Int; let localOffset: Int }
    private let data: [UInt8]
    private var entries: [String: Entry] = [:]
    var names: [String] { Array(entries.keys) }

    init(_ d: Data) throws {
        data = [UInt8](d)
        guard data.count > 22 else { throw SpreadsheetFiles.ReadError.notAWorkbook }
        // End of central directory: the last "PK\5\6" in the file.
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while i >= floor { if u32(i) == 0x0605_4B50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw SpreadsheetFiles.ReadError.notAWorkbook }
        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x0201_4B50 else { throw SpreadsheetFiles.ReadError.notAWorkbook }
            let nameLen = Int(u16(p + 28)), extra = Int(u16(p + 30)), comment = Int(u16(p + 32))
            guard p + 46 + nameLen <= data.count else { throw SpreadsheetFiles.ReadError.notAWorkbook }
            let name = String(decoding: data[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            entries[name] = Entry(method: u16(p + 10), compressed: Int(u32(p + 20)), size: Int(u32(p + 24)),
                                  localOffset: Int(u32(p + 42)))
            p += 46 + nameLen + extra + comment
        }
    }

    func file(_ name: String) -> Data? {
        guard let e = entries[name], e.localOffset + 30 <= data.count, u32(e.localOffset) == 0x0403_4B50 else { return nil }
        let start = e.localOffset + 30 + Int(u16(e.localOffset + 26)) + Int(u16(e.localOffset + 28))
        guard start + e.compressed <= data.count else { return nil }
        let raw = Array(data[start..<(start + e.compressed)])
        switch e.method {
        case 0: return Data(raw)
        case 8:
            guard e.size > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: e.size)
            // COMPRESSION_ZLIB is raw DEFLATE, the same as ZIP's method 8.
            let n = compression_decode_buffer(&out, e.size, raw, raw.count, nil, COMPRESSION_ZLIB)
            return n == e.size ? Data(out) : nil
        default: return nil
        }
    }

    private func u16(_ o: Int) -> UInt16 { UInt16(data[o]) | UInt16(data[o + 1]) << 8 }
    private func u32(_ o: Int) -> UInt32 {
        UInt32(data[o]) | UInt32(data[o + 1]) << 8 | UInt32(data[o + 2]) << 16 | UInt32(data[o + 3]) << 24
    }
}

// MARK: - XLSX XML

/// xl/sharedStrings.xml: every text cell points into this list.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    var current = ""
    var inText = false, inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let p = SharedStringsParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.strings
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch local(name) {
        case "si": current = ""
        case "t": inText = !inPhonetic
        case "rPh": inPhonetic = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch local(name) {
        case "si": strings.append(current)
        case "t": inText = false
        case "rPh": inPhonetic = false
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
}

/// A worksheet: <row><c r="B2" t="s"><v>3</v></c>…</row>. Cells are placed by their column letter,
/// because empty cells are left out of the file.
private final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    var row: [Int: String] = [:]
    var col = 0, type = "", value = "", inValue = false

    init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, shared: [String]) -> [[String]] {
        let p = SheetParser(shared: shared)
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.rows
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch local(name) {
        case "row": row = [:]; col = 0
        case "c":
            type = attributes["t"] ?? ""
            value = ""
            if let r = attributes["r"] { col = Self.column(r) }
        case "v", "t": inValue = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch local(name) {
        case "v", "t": inValue = false
        case "c":
            var text = value
            if type == "s", let i = Int(value), shared.indices.contains(i) { text = shared[i] }
            if type == "b" { text = value == "1" ? "TRUE" : "FALSE" }
            row[col] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            col += 1
        case "row":
            guard let last = row.keys.max() else { return }
            let cells = (0...last).map { row[$0] ?? "" }
            if cells.contains(where: { !$0.isEmpty }) { rows.append(cells) }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { value += string } }

    /// "B12" → 1, "AA3" → 26.
    static func column(_ ref: String) -> Int {
        var n = 0
        for u in ref.unicodeScalars {
            guard u.value >= 65, u.value <= 90 else { break }
            n = n * 26 + Int(u.value - 64)
        }
        return max(0, n - 1)
    }
}

private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
