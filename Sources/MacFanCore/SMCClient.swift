import CSMC
import Foundation

public enum SMCError: Error, Equatable {
    case unavailable
    case invalidKey
    case readFailed(String)
    case writeFailed(String)
    case unsupportedType(String)
}

public struct SMCValue: Equatable, Sendable {
    public let dataType: String
    public let bytes: [UInt8]

    public init(dataType: String, bytes: [UInt8]) {
        self.dataType = dataType
        self.bytes = bytes
    }

    public func doubleValue() throws -> Double {
        switch dataType {
        case "flt ":
            guard bytes.count == MemoryLayout<UInt32>.size else {
                throw SMCError.unsupportedType(dataType)
            }
            let bits: UInt32 = bytes.withUnsafeBytes { pointer in
                pointer.loadUnaligned(as: UInt32.self)
            }
            return Double(Float(bitPattern: UInt32(littleEndian: bits)))
        case "sp78":
            guard bytes.count == MemoryLayout<Int16>.size else {
                throw SMCError.unsupportedType(dataType)
            }
            let value: Int16 = bytes.withUnsafeBytes { pointer in
                pointer.loadUnaligned(as: Int16.self)
            }
            return Double(Int16(bigEndian: value)) / 256
        case "fpe2":
            return Double(try unsignedInteger(byteOrder: .big)) / 4
        case "ui8 ", "ui16", "ui32":
            return Double(try unsignedInteger(byteOrder: .big))
        default:
            throw SMCError.unsupportedType(dataType)
        }
    }

    public func unsignedInteger(byteOrder: ByteOrder) throws -> UInt32 {
        guard (1...4).contains(bytes.count) else {
            throw SMCError.unsupportedType(dataType)
        }

        let sequence: [UInt8] = byteOrder == .big
            ? bytes
            : Array(bytes.reversed())
        return sequence.reduce(0) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
    }
}

public enum ByteOrder: Sendable {
    case big
    case little
}

public final class SMCClient: @unchecked Sendable {
    private static let maximumDataSize: Int = 32
    private static let maximumTemperatureSensors: Int = 16

    private let connection: OpaquePointer
    private let lock: NSLock = NSLock()
    private var cachedTemperatureKeys: [String]?

    public init() throws {
        guard let connection: OpaquePointer = mf_smc_open() else {
            throw SMCError.unavailable
        }
        self.connection = connection
    }

    deinit {
        mf_smc_close(connection)
    }

    public func read(_ key: String) throws -> SMCValue {
        guard key.utf8.count == 4 else {
            throw SMCError.invalidKey
        }

        return try withLock {
            var bytes: [UInt8] = .init(repeating: 0, count: Self.maximumDataSize)
            var size: Int = 0
            var dataType: [CChar] = .init(repeating: 0, count: 5)

            let status: MFSMCStatus = key.withCString { keyPointer in
                mf_smc_read(
                    connection,
                    keyPointer,
                    &bytes,
                    bytes.count,
                    &size,
                    &dataType
                )
            }
            guard status == MFSMC_OK else {
                throw SMCError.readFailed(key)
            }

            return SMCValue(
                dataType: String(cString: dataType),
                bytes: Array(bytes.prefix(size))
            )
        }
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        guard key.utf8.count == 4 else {
            throw SMCError.invalidKey
        }

        try withLock {
            let status: MFSMCStatus = key.withCString { keyPointer in
                bytes.withUnsafeBytes { bytePointer in
                    guard let address: UnsafePointer<UInt8> = bytePointer.baseAddress?
                        .assumingMemoryBound(to: UInt8.self) else {
                        return MFSMC_INVALID_ARGUMENT
                    }
                    return mf_smc_write(connection, keyPointer, address, bytes.count)
                }
            }
            guard status == MFSMC_OK else {
                throw SMCError.writeFailed(key)
            }
        }
    }

    public func fanCount() throws -> Int {
        Int(try read("FNum").unsignedInteger(byteOrder: .big))
    }

    public func fanValue(index: Int, suffix: String) throws -> Double {
        try read("F\(index)\(suffix)").doubleValue()
    }

    public func setFanTarget(index: Int, rpm: Double) throws {
        try writeFloat("F\(index)Tg", value: Float(rpm))
    }

    public func setManualMode(index: Int, enabled: Bool) throws {
        let modeKeyCandidates: [String] = ["F\(index)Md", "F\(index)md"]
        let mode: UInt8 = enabled ? 1 : 0

        for key: String in modeKeyCandidates {
            if (try? write(key, bytes: [mode])) != nil {
                return
            }
        }

        if enabled {
            try write("Ftst", bytes: [1])
            for key: String in modeKeyCandidates {
                if (try? write(key, bytes: [mode])) != nil {
                    return
                }
            }
        }

        throw SMCError.writeFailed(modeKeyCandidates.joined(separator: ","))
    }

    public func restoreAutomaticControl(fanCount: Int) {
        for index: Int in 0..<fanCount {
            try? setManualMode(index: index, enabled: false)
        }
        try? write("Ftst", bytes: [0])
    }

    public func temperatureKeys() throws -> [String] {
        if let cachedTemperatureKeys {
            return cachedTemperatureKeys
        }

        let keyCount: Int = Int(try read("#KEY").unsignedInteger(byteOrder: .big))
        var candidates: [(key: String, temperature: Double)] = []

        for index: UInt32 in 0..<UInt32(keyCount) {
            guard let key: String = key(at: index),
                  key.first == "T",
                  let value: SMCValue = try? read(key),
                  value.dataType == "flt " || value.dataType == "sp78",
                  let temperature: Double = try? value.doubleValue(),
                  ThermalDefaults.sensorValidityRange.contains(temperature) else {
                continue
            }
            candidates.append((key: key, temperature: temperature))
        }

        let keys: [String] = candidates
            .sorted { $0.temperature > $1.temperature }
            .prefix(Self.maximumTemperatureSensors)
            .map(\.key)
        cachedTemperatureKeys = keys
        return keys
    }

    public func temperatures(keys: [String]) -> [String: Double] {
        keys.reduce(into: [:]) { result, key in
            guard let value: Double = try? read(key).doubleValue(),
                  ThermalDefaults.sensorValidityRange.contains(value) else {
                return
            }
            result[key] = value
        }
    }

    private func key(at index: UInt32) -> String? {
        withLock {
            var key: [CChar] = .init(repeating: 0, count: 5)
            guard mf_smc_key_at_index(connection, index, &key) == MFSMC_OK else {
                return nil
            }
            return String(cString: key)
        }
    }

    private func writeFloat(_ key: String, value: Float) throws {
        var bits: UInt32 = value.bitPattern.littleEndian
        let bytes: [UInt8] = withUnsafeBytes(of: &bits) { Array($0) }
        try write(key, bytes: bytes)
    }

    private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
