//
//  TopicFilterParser.swift
//  THAT
//
//  Created by Bailey Nahi on 29/04/2025.
//

import BigInt
import Foundation

struct TopicFilterParser {
    /// Approval(address indexed owner, address indexed spender, uint256 value) -> Approval(address,address,uint256)
    /// Transfer(address indexed from, address indexed to, uint256 value) -> Transfer(address,address,uint256)
    static func normalizedSignature(from annotatedSignature: String) -> String {
        guard let openParenIndex = annotatedSignature.firstIndex(of: "("),
              let closeParenIndex = annotatedSignature.lastIndex(of: ")")
        else { return annotatedSignature }
        
        let eventName = annotatedSignature[..<openParenIndex].trimmingCharacters(in: .whitespaces)
        let parameterListSubstring = annotatedSignature[annotatedSignature.index(after: openParenIndex)..<closeParenIndex]
        
        let rawParameters = parameterListSubstring.split(separator: ",")
        
        let normalizedParameters = rawParameters.map { param -> String in
            let withoutIndexed = param.replacingOccurrences(of: " indexed", with: "")
            let trimmed = withoutIndexed.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: " ")
            return parts.first.map(String.init) ?? ""
        }
        
        let parametersJoined = normalizedParameters.joined(separator: ",")
        return "\(eventName)(\(parametersJoined))"
    }
    
    /// Parses an event signature and returns an array of ABI types for each parameter.
    static func getAbiTypes(for eventSignature: String) -> [ABI.Element.ParameterType?] {
        guard let regex = try? NSRegularExpression(pattern: #"(\w+)\((.*)\)"#),
              let match = regex.firstMatch(in: eventSignature, range: NSRange(eventSignature.startIndex..., in: eventSignature)),
              let inputsRange = Range(match.range(at: 2), in: eventSignature)
        else {
            print("Invalid event signature")
            return []
        }
        
        let parametersString = eventSignature[inputsRange]
        let parameterStrings = parametersString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Use map so that every parameter is represented (even if nil)
        return parameterStrings.map { parseABIParameterType($0) }
    }
        
    /// Formats a raw topic filter value based on its ABI parameter type.
    /// - Parameters:
    ///   - abiType: The ABI parameter type (e.g. .address, .uint, .bool, etc.)
    ///   - rawValue: The raw string value, for example "0x61A748D6cF4F88466934854C5126B4c06844BD9c" for an address.
    /// - Returns: A hexadecimal string of 32 bytes (or an appropriate formatted value), or nil if conversion fails.
    static func formatTopicValue(for abiType: ABI.Element.ParameterType, rawValue: String) -> String? {
        switch abiType {
            case .address:
                // Ensure the address is padded to 32 bytes.
                return rawValue.paddedTo32Bytes().addHexPrefix()
            case .uint, .int:
                guard let bigInt = BigUInt(rawValue) else {
                    print("Invalid numeric value: \(rawValue) for type \(abiType)")
                    return nil
                }
                // Serializing a BigUInt returns Data. Convert to hex string and pad if needed.
                return bigInt.serialize().toHexString().addHexPrefix()
            case .bool:
                // Convert a boolean value to 0x1 or 0x0.
                return rawValue.lowercased() == "true" ? "0x1" : "0x0"
            case .string:
                // Here we hash the string.
                return rawValue.keccak256()?.addHexPrefix() ?? rawValue
            case .bytes:
                // Assume the user inputs a hex string; ensure it has "0x" prefix.
                return rawValue.addHexPrefix()
            default:
                print("Unsupported type for formatting: \(abiType)")
                return nil
        }
    }
    
    /// Parses the string representing of an ABI parameter type into an `ABI.Element.ParameterType`.
    static func parseABIParameterType(_ type: String) -> ABI.Element.ParameterType? {
        let lowercasedType = type.lowercased()
        switch lowercasedType {
            case "address": return .address
            case "bool": return .bool
            case "string": return .string
            case "bytes": return .dynamicBytes
            case let t where t.hasPrefix("uint"):
                let bits = UInt64(t.dropFirst(4)) ?? 256
                return .uint(bits: bits)
            case let t where t.hasPrefix("int"):
                let bits = UInt64(t.dropFirst(3)) ?? 256
                return .int(bits: bits)
            case let t where t.hasSuffix("[]"):
                if let subtype = parseABIParameterType(String(t.dropLast(2))) {
                    return .array(type: subtype, length: 0)
                }
                return nil
            default:
                return nil
        }
    }
}
