import Foundation

/// UAE banks and wallets, with the SMS sender IDs they commonly use.
/// Sender IDs change over time: the Shortcuts setup screen lets people add their own.
public struct Bank: Identifiable, Sendable, Hashable {
    public let id: String
    public let nameEN: String
    public let nameAR: String
    public let senderIDs: [String]
}

public enum BankDirectory {
    public static let all: [Bank] = [
        Bank(id: "fab",      nameEN: "First Abu Dhabi Bank", nameAR: "بنك أبوظبي الأول",       senderIDs: ["FAB", "FABBANK"]),
        Bank(id: "adcb",     nameEN: "ADCB",                 nameAR: "بنك أبوظبي التجاري",     senderIDs: ["ADCB", "ADCBAlert"]),
        Bank(id: "adib",     nameEN: "ADIB",                 nameAR: "مصرف أبوظبي الإسلامي",  senderIDs: ["ADIB"]),
        Bank(id: "enbd",     nameEN: "Emirates NBD",         nameAR: "الإمارات دبي الوطني",    senderIDs: ["EmiratesNBD", "ENBD"]),
        Bank(id: "liv",      nameEN: "Liv.",                 nameAR: "ليف",                    senderIDs: ["Liv", "LIVBANK"]),
        Bank(id: "dib",      nameEN: "Dubai Islamic Bank",   nameAR: "بنك دبي الإسلامي",       senderIDs: ["DIB"]),
        Bank(id: "mashreq",  nameEN: "Mashreq",              nameAR: "المشرق",                 senderIDs: ["Mashreq", "MashreqNEO"]),
        Bank(id: "cbd",      nameEN: "Commercial Bank of Dubai", nameAR: "بنك دبي التجاري",    senderIDs: ["CBD"]),
        Bank(id: "rak",      nameEN: "RAKBANK",              nameAR: "بنك رأس الخيمة",         senderIDs: ["RAKBANK"]),
        Bank(id: "eib",      nameEN: "Emirates Islamic",     nameAR: "الإمارات الإسلامي",      senderIDs: ["EIB", "EmiratesIsl"]),
        Bank(id: "wio",      nameEN: "Wio",                  nameAR: "ويو",                    senderIDs: ["Wio"]),
        Bank(id: "alhilal",  nameEN: "Al Hilal Bank",        nameAR: "مصرف الهلال",            senderIDs: ["AlHilal"]),
        Bank(id: "nbf",      nameEN: "NBF",                  nameAR: "بنك الفجيرة الوطني",     senderIDs: ["NBF"]),
        Bank(id: "hsbc",     nameEN: "HSBC UAE",             nameAR: "إتش إس بي سي",           senderIDs: ["HSBC"]),
        Bank(id: "tabby",    nameEN: "Tabby",                nameAR: "تابي",                   senderIDs: ["tabby"]),
        Bank(id: "tamara",   nameEN: "Tamara",               nameAR: "تمارا",                  senderIDs: ["Tamara"])
    ]

    public static func bankName(sender: String?, body: String) -> String? {
        // The sender exactly, or as a whole word ("AD-ADCB", "alerts@adcb.com"), never inside another name.
        if let s = sender?.lowercased(),
           let b = all.first(where: { $0.senderIDs.contains { s == $0.lowercased() || BankMessageParser.containsWord(s, $0.lowercased()) } }) {
            return b.nameEN
        }
        // Many banks sign the message body ("- ADCB", "Emirates NBD"). Whole words only there:
        // "liv" inside "delivered" or "DELIVEROO" is not Liv. `body` is already lower-cased.
        return all.first { b in
            b.senderIDs.contains { BankMessageParser.containsWord(body, $0.lowercased()) }
        }?.nameEN
    }
}
