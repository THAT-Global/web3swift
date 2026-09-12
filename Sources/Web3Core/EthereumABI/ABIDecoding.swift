//
//  Created by Alex Vlasov on 25/10/2018.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation
import BigInt

public struct ABIDecoder { }

extension ABIDecoder {
    public static func decode(types: [ABI.Element.InOut], data: Data) -> [Any]? {
        let params = types.compactMap { el -> ABI.Element.ParameterType in
            return el.type
        }
        return decode(types: params, data: data)
    }
    
    public static func decode(types: [ABI.Element.ParameterType], data: Data) -> [Any]? {
        var toReturn = [Any]()
        var consumed: UInt64 = 0
        for i in 0 ..< types.count {
            let (v, c) = decodeSingleType(type: types[i], data: data, pointer: consumed)
            guard let valueUnwrapped = v, let consumedUnwrapped = c else { return nil }
            toReturn.append(valueUnwrapped)
            // `decodeSingleType` returns the HEAD bytes the value occupies (see its
            // contract); the head pointer simply advances by that amount.
            consumed = consumed + consumedUnwrapped
        }
        guard toReturn.count == types.count else { return nil }
        return toReturn
    }
    
    /// Decodes one value of `type` whose HEAD begins at `pointer` within `data`.
    ///
    /// Returns the value and the number of HEAD bytes it occupies — `type.memoryUsage`:
    /// one 32-byte offset word for every dynamic type, the packed size for static
    /// types. Callers advance their head pointer by exactly that amount and never
    /// by anything else.
    ///
    /// THAT fork, 2026-09-05. Upstream returned an absolute "next element"
    /// pointer from the dynamic-bytes, dynamic-array-of-dynamic and dynamic-tuple
    /// arms and a byte COUNT from every other arm, and its three callers
    /// compensated inconsistently (the tuple arm special-cased arrays and tuples,
    /// the top-level loop nothing, the array loop assumed pointers). Net effect: a
    /// `bytes`, a `string[]` or a dynamic tuple in any position but the LAST
    /// shifted every later field, and a `string[]` of three or more elements
    /// repeated its second element. Found decoding EIP-3668
    /// `OffchainLookup(address,string[],bytes,bytes4,bytes)`; the payload is the
    /// fixture in `Tests/Web3CoreTests/ABIDecoderHeadTailTests.swift`.
    public static func decodeSingleType(type: ABI.Element.ParameterType, data: Data, pointer: UInt64 = 0) -> (value: Any?, bytesConsumed: UInt64?) {
        let (elData, nextPtr) = followTheData(type: type, data: data, pointer: pointer)
        guard let elementItself = elData, nextPtr != nil else {
            return (nil, nil)
        }
        let startIndex = UInt64(elementItself.startIndex)
        switch type {
            case .uint(let bits):
                guard elementItself.count >= 32 else {break}
                let mod = BigUInt(1) << bits
                let dataSlice = elementItself[startIndex ..< startIndex + 32]
                let v = BigUInt(dataSlice) % mod
                return (v, type.memoryUsage)
            case .int(let bits):
                guard elementItself.count >= 32 else {break}
                let mod = BigInt(1) << bits
                let dataSlice = elementItself[startIndex ..< startIndex + 32]
                let v = BigInt.fromTwosComplement(data: dataSlice) % mod
                return (v, type.memoryUsage)
            case .address:
                guard elementItself.count >= 32 else {break}
                let dataSlice = elementItself[startIndex + 12 ..< startIndex + 32]
                let address = EthereumAddress(dataSlice)
                return (address, type.memoryUsage)
            case .bool:
                guard elementItself.count >= 32 else {break}
                let dataSlice = elementItself[startIndex ..< startIndex + 32]
                let v = BigUInt(dataSlice)
                if v == BigUInt(36) ||
                    v == BigUInt(32) ||
                    v == BigUInt(28) ||
                    v == BigUInt(1) {
                    return (true, type.memoryUsage)
                } else if v == BigUInt(35) ||
                            v == BigUInt(31) ||
                            v == BigUInt(27) ||
                            v == BigUInt(0) {
                    return (false, type.memoryUsage)
                }
            case .bytes(let length):
                guard elementItself.count >= 32 else {break}
                let dataSlice = elementItself[startIndex ..< startIndex + length]
                return (Data(dataSlice), type.memoryUsage)
            case .string:
                guard elementItself.count >= 32 else {break}
                var dataSlice = elementItself[startIndex ..< startIndex + 32]
                let length = UInt64(BigUInt(dataSlice))
                guard elementItself.count >= 32 + length else {break}
                dataSlice = elementItself[32 ..< 32 + length]
                guard let string = String(data: dataSlice, encoding: .utf8) else {break}
                return (string, type.memoryUsage)
            case .dynamicBytes:
                guard elementItself.count >= 32 else {break}
                var dataSlice = elementItself[startIndex ..< startIndex + 32]
                let length = UInt64(BigUInt(dataSlice))
                guard elementItself.count >= 32 + length else {break}
                dataSlice = elementItself[startIndex + 32 ..< startIndex + 32 + length]
                return (Data(dataSlice), type.memoryUsage)
            case .array(type: let subType, length: let length):
                switch type.arraySize {
                    case .dynamicSize:
                        if subType.isStatic {
                            // uint[] like, expect length and elements
                            guard elementItself.count >= 32 else {break}
                            var dataSlice = elementItself[startIndex ..< startIndex + 32]
                            let length = UInt64(BigUInt(dataSlice))
                            guard elementItself.count >= 32 + subType.memoryUsage*length else {break}
                            dataSlice = elementItself[startIndex + 32 ..< startIndex + 32 + subType.memoryUsage*length]
                            var subpointer: UInt64 = 32
                            var toReturn = [Any]()
                            for _ in 0 ..< length {
                                let (v, c) = decodeSingleType(type: subType, data: elementItself, pointer: subpointer)
                                guard let valueUnwrapped = v, let consumedUnwrapped = c else {break}
                                toReturn.append(valueUnwrapped)
                                subpointer = subpointer + consumedUnwrapped
                            }
                            return (toReturn, type.memoryUsage)
                        } else {
                            // in principle is true for tuple[], so will work for string[] too
                            guard elementItself.count >= 32 else {break}
                            var dataSlice = elementItself[startIndex ..< startIndex + 32]
                            let length = UInt64(BigUInt(dataSlice))
                            guard elementItself.count >= 32 else {break}
                            dataSlice = Data(elementItself[startIndex + 32 ..< UInt64(elementItself.count)])
                            var subpointer: UInt64 = 0
                            var toReturn = [Any]()
                            for _ in 0 ..< length {
                                let (v, c) = decodeSingleType(type: subType, data: dataSlice, pointer: subpointer)
                                guard let valueUnwrapped = v, let consumedUnwrapped = c else {break}
                                toReturn.append(valueUnwrapped)
                                // One head word per element, whatever the subtype.
                                subpointer = subpointer + consumedUnwrapped
                            }
                            // The array itself is dynamic: one offset word in the parent's head.
                            return (toReturn, type.memoryUsage)
                        }
                    case .staticSize(let staticLength):
                        guard length == staticLength else {break}
                        var toReturn = [Any]()
                        var consumed: UInt64 = 0
                        for _ in 0 ..< length {
                            let (v, c) = decodeSingleType(type: subType, data: elementItself, pointer: consumed)
                            guard let valueUnwrapped = v, let consumedUnwrapped = c else {return (nil, nil)}
                            toReturn.append(valueUnwrapped)
                            consumed = consumed + consumedUnwrapped
                        }
                        if subType.isStatic {
                            return (toReturn, consumed)
                        } else {
                            // Dynamic elements make the array dynamic: one offset word in the parent's head.
                            return (toReturn, type.memoryUsage)
                        }
                    case .notArray:
                        break
                }
            case .tuple(types: let subTypes):
                var toReturn = [Any]()
                var consumed: UInt64 = 0
                for i in 0 ..< subTypes.count {
                    let (v, c) = decodeSingleType(type: subTypes[i], data: elementItself, pointer: consumed)
                    guard let valueUnwrapped = v, let consumedUnwrapped = c else {return (nil, nil)}
                    toReturn.append(valueUnwrapped)
                    consumed = consumed + consumedUnwrapped
                }
                if type.isStatic {
                    return (toReturn, consumed)
                } else {
                    // A dynamic tuple occupies one offset word in its parent's head.
                    return (toReturn, type.memoryUsage)
                }
            case .function:
                guard elementItself.count >= 32 else {break}
                let dataSlice = elementItself[startIndex + 8 ..< startIndex + 32]
                return (Data(dataSlice), type.memoryUsage)
        }
        return (nil, nil)
    }
    
    fileprivate static func followTheData(type: ABI.Element.ParameterType, data: Data, pointer: UInt64 = 0) -> (elementEncoding: Data?, nextElementPointer: UInt64?) {
        if type.isStatic {
            guard data.count >= pointer + type.memoryUsage else {return (nil, nil)}
            let elementItself = data[data.startIndex + Int(pointer) ..< data.startIndex + Int(pointer + type.memoryUsage)]
            let nextElement = pointer + type.memoryUsage
            return (Data(elementItself), nextElement)
        } else {
            guard data.count >= pointer + type.memoryUsage else {return (nil, nil)}
            let dataSlice = data[data.startIndex + Int(pointer) ..< data.startIndex + Int(pointer + type.memoryUsage)]
            let bn = BigUInt(dataSlice)
            if bn > UInt64.max || bn >= data.count {
                // there are ERC20 contracts that use bytes32 instead of string. Let's be optimistic and return some data
                if case .string = type {
                    let nextElement = pointer + type.memoryUsage
                    let preambula = BigUInt(32).abiEncode(bits: 256)!
                    return (preambula + Data(dataSlice), nextElement)
                } else if case .dynamicBytes = type {
                    let nextElement = pointer + type.memoryUsage
                    let preambula = BigUInt(32).abiEncode(bits: 256)!
                    return (preambula + Data(dataSlice), nextElement)
                }
                return (nil, nil)
            }
            let elementPointer = UInt64(bn)
            let startIndex = UInt64(data.startIndex)
            let elementItself = data[startIndex + elementPointer ..< startIndex + UInt64(data.count)]
            let nextElement = pointer + type.memoryUsage
            return (Data(elementItself), nextElement)
        }
    }
    
    public static func decodeLog(event: ABI.Element.Event, eventLogTopics: [Data], eventLogData: Data) -> [String: Any]? {
        if event.topic != eventLogTopics[0] && !event.anonymous {
            return nil
        }
        var eventContent = [String: Any]()
        eventContent["name"]=event.name
        let logs = eventLogTopics
        let dataForProcessing = eventLogData
        let indexedInputs = event.inputs.filter { inp -> Bool in
            return inp.indexed
        }
        if logs.count == 1 && indexedInputs.count > 0 {
            return nil
        }
        let nonIndexedInputs = event.inputs.filter { inp -> Bool in
            return !inp.indexed
        }
        let nonIndexedTypes = nonIndexedInputs.compactMap { inp -> ABI.Element.ParameterType in
            return inp.type
        }
        guard logs.count == indexedInputs.count + 1 else { return nil }
        var indexedValues = [Any]()
        for i in 0 ..< indexedInputs.count {
            let data = logs[i+1]
            let input = indexedInputs[i]
            if !input.type.isStatic || input.type.isArray || input.type.memoryUsage != 32 {
                let (v, _) = ABIDecoder.decodeSingleType(type: .bytes(length: 32), data: data)
                guard let valueUnwrapped = v else { return nil }
                indexedValues.append(valueUnwrapped)
            } else {
                let (v, _) = ABIDecoder.decodeSingleType(type: input.type, data: data)
                guard let valueUnwrapped = v else { return nil }
                indexedValues.append(valueUnwrapped)
            }
        }
        let v = ABIDecoder.decode(types: nonIndexedTypes, data: dataForProcessing)
        guard let nonIndexedValues = v else { return nil }
        var indexedInputCounter = 0
        var nonIndexedInputCounter = 0
        for i in 0 ..< event.inputs.count {
            let el = event.inputs[i]
            if el.indexed {
                let name = "\(i)"
                let value = indexedValues[indexedInputCounter]
                eventContent[name] = value
                if el.name != "" {
                    eventContent[el.name] = value
                }
                indexedInputCounter = indexedInputCounter + 1
            } else {
                let name = "\(i)"
                let value = nonIndexedValues[nonIndexedInputCounter]
                eventContent[name] = value
                if el.name != "" {
                    eventContent[el.name] = value
                }
                nonIndexedInputCounter = nonIndexedInputCounter + 1
            }
        }
        return eventContent
    }
}
