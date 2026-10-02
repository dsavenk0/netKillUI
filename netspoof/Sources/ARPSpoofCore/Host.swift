import Foundation

/// Обнаруженный в сети хост. Общая модель для CLI, serve-режима и GUI.
public struct Host: Equatable {
    public let ip: IPv4Address
    public let mac: MACAddress
    public var name: String?

    public init(ip: IPv4Address, mac: MACAddress, name: String? = nil) {
        self.ip = ip
        self.mac = mac
        self.name = name
    }

    /// Производитель по OUI (или "Unknown").
    public var vendor: String { ARPSpoofCore.vendor(for: mac) }
}
