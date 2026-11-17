// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import Foundation
import zlib

enum QRCodeImportPreparationError: Error {
    case emptyPayload
    case invalidVPNPayload
    case malformedVPNPayload
    case compressedPayloadEmpty
    case zlibDecodeFailed
    case decompressedLengthMismatch(expected: Int, actual: Int)
    case malformedJSON
    case missingConfig
    case unresolvedDNSPlaceholder
}

extension QRCodeImportPreparationError {
    var alertMessage: String {
        switch self {
        case .emptyPayload:
            return "二维码内容为空。"
        case .invalidVPNPayload:
            return "二维码中的 vpn:// 链接内容不是有效的 Base64URL 数据。"
        case .malformedVPNPayload:
            return "二维码中的 vpn:// 链接数据结构不完整。"
        case .compressedPayloadEmpty:
            return "二维码中的 vpn:// 链接缺少压缩数据段。"
        case .zlibDecodeFailed:
            return "二维码中的 vpn:// 链接 zlib 解压失败，数据可能损坏或不是预期格式。"
        case let .decompressedLengthMismatch(expected, actual):
            return "二维码中的 vpn:// 链接解压长度不匹配（期望 \(expected)，实际 \(actual)）。"
        case .malformedJSON:
            return "二维码中的 vpn:// 链接内容不是有效的配置数据。"
        case .missingConfig:
            return "二维码中的 vpn:// 链接缺少可导入的 WireGuard 配置。"
        case .unresolvedDNSPlaceholder:
            return "二维码中的 vpn:// 链接缺少 DNS 信息，无法生成可导入配置。"
        }
    }
}

enum QRCodeImportPreprocessor {
    static func configText(from scannedCode: String) throws -> String {
        let trimmed = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QRCodeImportPreparationError.emptyPayload
        }

        if trimmed.lowercased().hasPrefix("vpn://") {
            return try decodeVPNLink(trimmed)
        }

        return trimmed
    }

    private static func decodeVPNLink(_ link: String) throws -> String {
        let payload = String(link.dropFirst("vpn://".count))
            .unicodeScalars
            .filter { scalar in
                (scalar.value >= 48 && scalar.value <= 57) ||   // 0-9
                (scalar.value >= 65 && scalar.value <= 90) ||   // A-Z
                (scalar.value >= 97 && scalar.value <= 122) ||  // a-z
                scalar == "-" || scalar == "_"
            }
            .map(String.init)
            .joined()

        guard let rawData = Data(base64URLEncoded: payload) else {
            throw QRCodeImportPreparationError.invalidVPNPayload
        }

        guard rawData.count > 4 else {
            throw QRCodeImportPreparationError.malformedVPNPayload
        }

        let expectedJSONLength = Int(rawData.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) })
        guard expectedJSONLength > 0 else {
            throw QRCodeImportPreparationError.malformedVPNPayload
        }

        let compressedPayload = Data(rawData.dropFirst(4))
        let jsonData = try decompressZlib(compressedPayload, expectedSize: expectedJSONLength)

        guard jsonData.count == expectedJSONLength else {
            throw QRCodeImportPreparationError.decompressedLengthMismatch(expected: expectedJSONLength, actual: jsonData.count)
        }

        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw QRCodeImportPreparationError.malformedJSON
        }

        guard let containers = root["containers"] as? [[String: Any]],
              let firstContainer = containers.first,
              let awg = firstContainer["awg"] as? [String: Any],
              let lastConfigJSONString = awg["last_config"] as? String,
              let lastConfigData = lastConfigJSONString.data(using: .utf8),
              let lastConfigRoot = try? JSONSerialization.jsonObject(with: lastConfigData) as? [String: Any],
              let rawConfig = lastConfigRoot["config"] as? String,
              !rawConfig.isEmpty else {
            throw QRCodeImportPreparationError.malformedVPNPayload
        }

        let dns1 = root["dns1"] as? String
        let dns2 = root["dns2"] as? String

        var resolvedConfig = rawConfig

        if let dns1 = dns1 {
            resolvedConfig = resolvedConfig.replacingOccurrences(of: "$PRIMARY_DNS", with: dns1)
        }
        if let dns2 = dns2 {
            resolvedConfig = resolvedConfig.replacingOccurrences(of: "$SECONDARY_DNS", with: dns2)
        }

        if resolvedConfig.contains("$PRIMARY_DNS") || resolvedConfig.contains("$SECONDARY_DNS") {
            throw QRCodeImportPreparationError.unresolvedDNSPlaceholder
        }

        return resolvedConfig
    }

    private static func decompressZlib(_ compressedData: Data, expectedSize: Int) throws -> Data {
        guard !compressedData.isEmpty else {
            throw QRCodeImportPreparationError.compressedPayloadEmpty
        }

        var stream = z_stream()
        let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw QRCodeImportPreparationError.zlibDecodeFailed
        }
        defer { inflateEnd(&stream) }

        let chunkSize = max(1024, min(64 * 1024, expectedSize))

        return try compressedData.withUnsafeBytes { rawBuffer in
            guard let sourcePointer = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw QRCodeImportPreparationError.zlibDecodeFailed
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourcePointer)
            stream.avail_in = uInt(compressedData.count)

            var output = Data()
            var finished = false

            while !finished {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let inflateStatus: Int32 = chunk.withUnsafeMutableBufferPointer { buffer in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }

                if output.count > expectedSize {
                    throw QRCodeImportPreparationError.decompressedLengthMismatch(expected: expectedSize, actual: output.count)
                }

                switch inflateStatus {
                case Z_STREAM_END:
                    finished = true
                case Z_OK:
                    if produced == 0 && stream.avail_in == 0 {
                        throw QRCodeImportPreparationError.zlibDecodeFailed
                    }
                default:
                    throw QRCodeImportPreparationError.zlibDecodeFailed
                }
            }

            guard output.count == expectedSize else {
                throw QRCodeImportPreparationError.decompressedLengthMismatch(expected: expectedSize, actual: output.count)
            }

            return output
        }
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }

        self.init(base64Encoded: normalized)
    }
}
