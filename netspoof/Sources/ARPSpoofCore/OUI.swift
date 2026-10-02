
import Foundation

/// Резолв производителя по первым трём байтам MAC (OUI).
/// Подмножество IEEE-реестра — самые частые в домашних/офисных сетях.
/// Полный oui.txt можно подложить позже, формат лукапа не изменится.
public func vendor(for mac: MACAddress) -> String {
    let prefix = mac.bytes.prefix(3)
        .map { String(format: "%02X", $0) }
        .joined(separator: ":")
    return ouiTable[prefix] ?? "Unknown"
}

let ouiTable: [String: String] = [
    // Apple
    "3C:22:FB": "Apple", "F0:18:98": "Apple", "A4:83:E7": "Apple",
    "AC:DE:48": "Apple", "DC:A9:04": "Apple", "88:66:5A": "Apple",
    "F4:0F:24": "Apple", "00:1B:63": "Apple", "00:03:93": "Apple",
    "6C:40:08": "Apple", "A8:5C:2C": "Apple", "9C:20:7B": "Apple",
    // Samsung
    "A0:0B:BA": "Samsung Electronics", "5C:0A:5B": "Samsung Electronics",
    "34:23:BA": "Samsung Electronics", "00:12:FB": "Samsung Electronics",
    "08:08:C2": "Samsung Electronics", "B4:07:F9": "Samsung Electronics",
    "EC:1F:72": "Samsung Electronics",
    // Raspberry Pi
    "B8:27:EB": "Raspberry Pi", "DC:A6:32": "Raspberry Pi",
    "E4:5F:01": "Raspberry Pi", "28:CD:C1": "Raspberry Pi",
    "D8:3A:DD": "Raspberry Pi", "2C:CF:67": "Raspberry Pi",
    // Espressif (ESP8266/ESP32 — IoT)
    "24:0A:C4": "Espressif", "30:AE:A4": "Espressif", "7C:9E:BD": "Espressif",
    "A0:20:A6": "Espressif", "DC:4F:22": "Espressif", "84:F3:EB": "Espressif",
    "B4:E6:2D": "Espressif", "C4:4F:33": "Espressif",
    // Intel
    "00:1B:21": "Intel", "3C:FD:FE": "Intel", "A4:C3:F0": "Intel",
    "34:13:E8": "Intel", "94:65:9C": "Intel", "7C:B0:C2": "Intel",
    // Networking gear
    "00:1A:2B": "Cisco", "00:0C:29": "VMware", "00:50:56": "VMware",
    "50:C7:BF": "TP-Link", "C4:6E:1F": "TP-Link", "AC:84:C6": "TP-Link",
    "B0:4E:26": "TP-Link", "E8:94:F6": "TP-Link",
    "20:4E:7F": "Netgear", "A0:40:A0": "Netgear", "9C:3D:CF": "Netgear",
    "C0:3F:0E": "Netgear", "DC:EF:09": "Xiaomi", "64:09:80": "Xiaomi",
    "F8:A4:5F": "Xiaomi", "28:6C:07": "Xiaomi", "50:EC:50": "Xiaomi",
    "00:9E:C8": "Xiaomi",
    // Amazon / Google / Microsoft / Sony / LG / Huawei
    "FC:A1:83": "Amazon", "44:65:0D": "Amazon", "68:54:FD": "Amazon",
    "1C:12:B0": "Amazon", "F4:F5:D8": "Google", "D8:6C:63": "Google",
    "54:60:09": "Google", "00:15:5D": "Microsoft", "00:50:F2": "Microsoft",
    "7C:1E:52": "Microsoft", "AC:9B:0A": "Sony", "FC:F1:52": "Sony",
    "00:1E:75": "LG Electronics", "A8:16:B2": "LG Electronics",
    "48:3B:38": "Huawei", "00:E0:FC": "Huawei", "20:F3:A3": "Huawei",
]
