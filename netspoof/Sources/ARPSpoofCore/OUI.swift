
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
    // Роутеры / сетевое
    "DC:2C:6E": "MikroTik", "64:D1:54": "MikroTik", "48:8F:5A": "MikroTik",
    "6C:3B:6B": "MikroTik", "CC:2D:E0": "MikroTik", "74:4D:28": "MikroTik",
    "E4:8D:8C": "MikroTik", "B8:69:F4": "MikroTik", "2C:C8:1B": "MikroTik",
    "50:FF:20": "Keenetic",
    "04:18:D6": "Ubiquiti", "24:A4:3C": "Ubiquiti", "44:D9:E7": "Ubiquiti",
    "78:8A:20": "Ubiquiti", "FC:EC:DA": "Ubiquiti", "DC:9F:DB": "Ubiquiti",
    "68:D7:9A": "Ubiquiti", "E0:63:DA": "Ubiquiti", "74:AC:B9": "Ubiquiti",
    "2C:56:DC": "ASUSTek", "50:46:5D": "ASUSTek", "AC:22:0B": "ASUSTek",
    "04:D4:C4": "ASUSTek", "38:D5:47": "ASUSTek", "1C:87:2C": "ASUSTek",
    "1C:7E:E5": "D-Link", "34:08:04": "D-Link", "00:1E:58": "D-Link",
    "C8:BE:19": "D-Link", "78:54:2E": "D-Link",
    "5C:E2:8C": "Zyxel", "B0:B2:DC": "Zyxel", "A0:E4:CB": "Zyxel", "00:19:CB": "Zyxel",
    // Чипы / виртуализация
    "00:E0:4C": "Realtek", "52:54:00": "Realtek/QEMU", "00:10:18": "Broadcom",
    // Медиа / умный дом
    "00:0E:58": "Sonos", "34:7E:5C": "Sonos", "48:A6:B8": "Sonos",
    "94:9F:3E": "Sonos", "5C:AA:FD": "Sonos", "B8:E9:37": "Sonos",
    "DC:3A:5E": "Roku", "B0:A7:37": "Roku", "CC:6D:A0": "Roku", "D8:31:34": "Roku",
    "00:04:4B": "NVIDIA", "48:B0:2D": "NVIDIA",
    "1C:F2:9A": "Google", "30:FD:38": "Google", "20:DF:B9": "Google",
    "68:37:E9": "Amazon", "0C:47:C9": "Amazon", "FC:65:DE": "Amazon", "74:C2:46": "Amazon",
    "C8:19:F7": "Samsung Electronics", "E8:50:8B": "Samsung Electronics",
]
