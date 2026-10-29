#!/usr/bin/env swift
import CommonCrypto
import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let json = arguments.first, let payload = json.data(using: .utf8),
      (try? JSONSerialization.jsonObject(with: payload)) != nil else {
    print("""
    usage: bin/club-code.swift '<reward json>' [CODE]
      reward keys: tier ("founder"|"supporter"), years (Int), titles ([String]), stickers ([String] or ["*"]), icons (Bool), pet (Bool)
      example: bin/club-code.swift '{"tier":"founder","titles":["Wetterfrosch"]}'
    """)
    exit(1)
}

var bytes = [UInt8](repeating: 0, count: 6)
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
let code = String((arguments.dropFirst().first ?? bytes.map { String(format: "%02X", $0) }.joined()).uppercased().filter(\.isHexDigit).prefix(12))
guard code.count == 12 else {
    print("CODE must be 12 hex characters")
    exit(1)
}

let password = Array(code.utf8)
let salt = Array("oscar.club.v1".utf8)
var derived = [UInt8](repeating: 0, count: 32)
_ = CCKeyDerivationPBKDF(
    CCPBKDFAlgorithm(kCCPBKDF2),
    password.map { Int8(bitPattern: $0) }, password.count,
    salt, salt.count,
    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 300_000,
    &derived, derived.count
)
let key = SymmetricKey(data: derived)
let id = SHA256.hash(data: Data(derived)).prefix(16).map { String(format: "%02x", $0) }.joined()
let box = try AES.GCM.seal(payload, using: key).combined!.base64EncodedString()

let grouped = stride(from: 0, to: 12, by: 4).map { start -> String in
    let begin = code.index(code.startIndex, offsetBy: start)
    return String(code[begin..<code.index(begin, offsetBy: 4)])
}.joined(separator: "-")

print("code:  \(grouped)")
print("table: \"\(id)\": \"\(box)\",")
