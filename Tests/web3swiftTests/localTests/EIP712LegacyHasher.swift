//
//  EIP712LegacyHasher.swift
//  localTests
//
//  The fork's EIP-712 hashing as it was before 5.1.0 (`Sources/Web3Swift/Utils/EIP/EIP712/EIP712Parser.swift` at
//  develop d1cef1b5), kept for the differential cell (EIP712DifferentialTests) and reachable from tests alone. The code
//  below is that file's, with its types renamed (`Legacy…`), `public` dropped, its doc comments cut, and
//  `asJsonDictionary()` written out. Its defects are the point: a fixed-size array (`bool[2]`) is encoded in place, an
//  array of structs `Leg[2]` throws, and `encodeType` appends each child's whole subtree and sorts only direct children.
//  Nothing outside the test target can call it.
//

import CryptoSwift
import Foundation
import Web3Core

class LegacyEIP712Parser {
    
    static func toData(_ json: String) throws -> Data {
        guard let json = json.data(using: .utf8) else {
            throw Web3Error.inputError(desc: "EIP712Parser. Failed to parse EIP712 payload. Given string is not valid UTF8 string.")
        }
        return json
    }
    
    static func parse(_ rawJson: String) throws -> LegacyEIP712TypedData {
        try parse(try toData(rawJson))
    }
    
    static func parse(_ rawJson: Data) throws -> LegacyEIP712TypedData {
        let decoder = JSONDecoder()
        let types = try decoder.decode(LegacyEIP712TypeArray.self, from: rawJson).types
        guard let json = try JSONSerialization.jsonObject(with: rawJson, options: .mutableContainers) as? [String: AnyObject] else {
            throw Web3Error.inputError(desc: "EIP712Parser. Cannot decode given JSON as it cannot be represented as a Dictionary. Is it valid JSON?")
        }
        guard let primaryType = json["primaryType"] as? String else {
            throw Web3Error.inputError(desc: "EIP712Parser. Top-level string field 'primaryType' missing.")
        }
        guard let domain = json["domain"] as? [String : AnyObject] else {
            throw Web3Error.inputError(desc: "EIP712Parser. Top-level object field 'domain' missing.")
        }
        guard let message = json["message"] as? [String : AnyObject] else {
            throw Web3Error.inputError(desc: "EIP712Parser. Top-level object field 'message' missing.")
        }
        return try LegacyEIP712TypedData(types: types, primaryType: primaryType, domain: domain, message: message)
    }
}

internal struct LegacyEIP712TypeArray: Codable {
    let types: [String : [LegacyEIP712TypeProperty]]
}

struct LegacyEIP712TypeProperty: Codable {
    let name: String
    let type: String
    let coreType: String
    
    let isArray: Bool
    
    init(name: String, type: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var _coreType = self.type
        if _coreType.hasSuffix("[]") {
            _coreType.removeLast(2)
            isArray = true
        } else {
            isArray = false
        }
        self.coreType = _coreType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let type = try container.decode(String.self, forKey: .type)
        self.init(name: name, type: type)
    }
}

struct LegacyEIP712TypedData {
    let types: [String: [LegacyEIP712TypeProperty]]
    let primaryType: String
    let domain: [String : AnyObject]
    let message: [String : AnyObject]
    
    init(types: [String : [LegacyEIP712TypeProperty]],
                primaryType: String,
                domain: [String : AnyObject],
                message: [String : AnyObject]) throws {
        self.types = types
        self.primaryType = primaryType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain
        self.message = message
    }
    
    func encodeType(_ type: String) throws -> String {
        guard let typeData = types[type] else {
            throw Web3Error.processingError(desc: "EIP712Parser. Attempting to encode type that doesn't exist in this payload. Given type: \(type). Available types: \(types.keys).")
        }
        return try encodeType(type, typeData)
    }
    
    func typeHash(_ type: String) throws -> String {
        try encodeType(type).sha3(.keccak256).addHexPrefix()
    }
    
    internal func encodeType(_ type: String, _ typeData: [LegacyEIP712TypeProperty], typesCovered: [String] = []) throws -> String {
        var typesCovered = typesCovered
        var encodedSubtypes: [String : String] = [:]
        let parameters = try typeData.map { attributeType in
            if let innerTypes = types[attributeType.coreType], !typesCovered.contains(attributeType.coreType) {
                typesCovered.append(attributeType.coreType)
                if attributeType.coreType != type {
                    encodedSubtypes[attributeType.coreType] = try encodeType(attributeType.coreType, innerTypes)
                }
            }
            return "\(attributeType.type) \(attributeType.name)"
        }
        return type + "(" + parameters.joined(separator: ",") + ")" + encodedSubtypes.sorted { lhs, rhs in
            return lhs.key < rhs.key
        }
        .map { $0.value }
        .joined(separator: "")
    }
    
    func encodeData() throws -> Data {
        try encodeData(primaryType, data: message)
    }
    
    func encodeData(_ type: String, data: [String : AnyObject]) throws -> Data {
        // Adding typehash
        var encTypes: [ABI.Element.ParameterType] = [.bytes(length: 32)]
        var encValues: [Any] = [try typeHash(type)]
        
        guard let typeData = types[type] else {
            throw Web3Error.processingError(desc: "EIP712Parser. Attempting to encode data for type that doesn't exist in this payload. Given type: \(type). Available types: \(types.keys).")
        }
        
        func encodeField(_ field: LegacyEIP712TypeProperty,
                         value: AnyObject?) throws -> (encTypes: [ABI.Element.ParameterType], encValues: [Any]) {
            var encTypes: [ABI.Element.ParameterType] = []
            var encValues: [Any] = []
            if field.type == "string" {
                guard let value = value as? String else {
                    throw Web3Error.processingError(desc: "EIP712Parser. Type metadata of '\(field)' and actual value '\(String(describing: value))' type doesn't match. Cannot cast value to String. Parent object type: \(type).")
                }
                encTypes.append(.bytes(length: 32))
                encValues.append(value.sha3(.keccak256).addHexPrefix())
            } else if field.type == "bytes"{
                let _value: Data?
                if let value = value as? String,
                   let data = Data.fromHex(value) {
                    _value = data
                } else {
                    _value = value as? Data
                }
                guard let value = _value else {
                    throw Web3Error.processingError(desc: "EIP712Parser. Type metadata '\(field)' and actual value '\(String(describing: value))' type doesn't match. Cannot cast/parse value to Data. Parent object type: \(type).")
                }
                encTypes.append(.bytes(length: 32))
                encValues.append(value.sha3(.keccak256))
            } else if field.isArray {
                guard let values = value as? [AnyObject] else {
                    throw Web3Error.processingError(desc: "EIP712Parser. Custom type metadata '\(field)' and actual value '\(String(describing: value))' type doesn't match. Cannot cast value to [AnyObject]. Parent object type: \(type)")
                }
                encTypes.append(.bytes(length: 32))
                let subField = LegacyEIP712TypeProperty(name: field.name, type: field.coreType)
                var encodedSubTypes: [ABI.Element.ParameterType] = []
                var encodedSubValues: [Any] = []
                try values.forEach { value in
                    let encoded = try encodeField(subField, value: value)
                    encodedSubTypes.append(contentsOf: encoded.encTypes)
                    encodedSubValues.append(contentsOf: encoded.encValues)
                }
                
                guard let encodedValue = ABIEncoder.encode(types: encodedSubTypes, values: encodedSubValues) else {
                    throw Web3Error.processingError(desc: "EIP712Parser. Failed to encode an array of custom type. Field: '\(field)'; value: '\(String(describing: value))'. Parent object type: \(type)")
                }
                
                encValues.append(encodedValue.sha3(.keccak256))
            } else if types[field.coreType] != nil  {
                encTypes.append(.bytes(length: 32))
                if let value = value as? [String : AnyObject] {
                    encValues.append(try encodeData(field.type, data: value).sha3(.keccak256))
                } else {
                    encValues.append(Data(count: 32))
                }
            } else {
                encTypes.append(try ABITypeParser.parseTypeString(field.type))
                encValues.append(value as Any)
            }
            return (encTypes, encValues)
        }
        
        // Add field contents
        for field in typeData {
            let (_encTypes, _encValues) = try encodeField(field, value: data[field.name])
            encTypes.append(contentsOf: _encTypes)
            encValues.append(contentsOf: _encValues)
        }
        
        guard let encodedData = ABIEncoder.encode(types: encTypes, values: encValues) else {
            throw Web3Error.processingError(desc: "EIP712Parser. ABIEncoder.encode failed with the following types and values: \(encTypes); \(encValues)")
        }
        return encodedData
    }
    
    func structHash() throws -> Data {
        try structHash(primaryType, data: message)
    }
    
    func structHash(_ type: String, data: [String : AnyObject]) throws -> Data {
        try encodeData(type, data: data).sha3(.keccak256)
    }
    
    func signHash() throws -> Data {
        try (Data.fromHex("0x1901")! + structHash("EIP712Domain", data: domain) + structHash()).sha3(.keccak256)
    }
}
