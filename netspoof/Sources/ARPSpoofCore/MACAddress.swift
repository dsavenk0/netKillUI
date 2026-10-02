import Foundation

public struct MACAddress: Equatable, Hashable, CustomStringConvertible {
    public let bytes: [UInt8] // всегда 6

    public init(bytes: [UInt8]) {
        precondition(bytes.count == 6, "MAC должен быть из 6 байт")
        self.bytes = bytes
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var b = [UInt8]()
        b.reserveCapacity(6)
        for p in parts {
            guard let v = UInt8(p, radix: 16) else { return nil }
            b.append(v)
        }
        self.bytes = b
    }

    public static let broadcast = MACAddress(bytes: [0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
    public static let zero = MACAddress(bytes: [0, 0, 0, 0, 0, 0])

    public var description: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
