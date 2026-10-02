import Testing
@testable import ARPSpoofCore

// MARK: MACAddress

@Test func macParseRoundtrip() throws {
    let mac = try #require(MACAddress("a0:0b:ba:f8:ee:de"))
    #expect(mac.bytes == [0xa0, 0x0b, 0xba, 0xf8, 0xee, 0xde])
    #expect(mac.description == "a0:0b:ba:f8:ee:de")
}

@Test func macRejectsBadInput() {
    #expect(MACAddress("zz:zz:zz:zz:zz:zz") == nil)
    #expect(MACAddress("a0:0b:ba:f8:ee") == nil)      // слишком коротко
    #expect(MACAddress("a0-0b-ba-f8-ee-de") == nil)   // не те разделители
}

@Test func macConstants() {
    #expect(MACAddress.broadcast.bytes == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
    #expect(MACAddress.zero.bytes == [0, 0, 0, 0, 0, 0])
}

// MARK: IPv4Address

@Test func ipv4ParseAndOctetOrder() throws {
    let ip = try #require(IPv4Address("192.168.100.6"))
    #expect(ip.bytes == [192, 168, 100, 6])
    #expect(ip.description == "192.168.100.6")
}

@Test func ipv4HostOrderRoundtrip() throws {
    let ip = try #require(IPv4Address("10.0.0.1"))
    #expect(ip.hostOrder == 0x0A000001)
    #expect(IPv4Address(hostOrder: ip.hostOrder) == ip)
}

@Test func ipv4RejectsBadInput() {
    #expect(IPv4Address("999.1.1.1") == nil)
    #expect(IPv4Address("abc") == nil)
}

@Test func subnetEnumeration24() throws {
    let ip = try #require(IPv4Address("192.168.100.6"))
    let mask = try #require(IPv4Address("255.255.255.0"))
    let hosts = hostsInSubnet(ip: ip, mask: mask)
    #expect(hosts.count == 254)                             // .1 … .254
    #expect(hosts.first?.description == "192.168.100.1")
    #expect(hosts.last?.description == "192.168.100.254")
    #expect(!hosts.contains(try #require(IPv4Address("192.168.100.0"))))   // network
    #expect(!hosts.contains(try #require(IPv4Address("192.168.100.255")))) // broadcast
}

@Test func subnetCapRespected() throws {
    let ip = try #require(IPv4Address("10.0.0.5"))
    let mask = try #require(IPv4Address("255.255.0.0")) // /16 → много хостов
    #expect(hostsInSubnet(ip: ip, mask: mask, cap: 50).count == 50)
}

// MARK: ARP frame build/parse

@Test func buildARPFrameShape() throws {
    let f = buildARPFrame(op: .reply,
                          senderMAC: try #require(MACAddress("aa:bb:cc:dd:ee:ff")),
                          senderIP: try #require(IPv4Address("192.168.1.1")),
                          targetMAC: try #require(MACAddress("11:22:33:44:55:66")),
                          targetIP: try #require(IPv4Address("192.168.1.50")),
                          ethDst: try #require(MACAddress("11:22:33:44:55:66")),
                          ethSrc: try #require(MACAddress("aa:bb:cc:dd:ee:ff")))
    #expect(f.count == 60)                        // паддинг до минимального кадра
    #expect(Array(f[12...13]) == [0x08, 0x06])    // ethertype ARP
    #expect(Array(f[20...21]) == [0x00, 0x02])    // op = reply
    #expect(Array(f[0...5]) == [0x11, 0x22, 0x33, 0x44, 0x55, 0x66]) // eth dst
}

@Test func buildThenParseReply() throws {
    let senderMAC = try #require(MACAddress("aa:bb:cc:dd:ee:ff"))
    let senderIP = try #require(IPv4Address("192.168.1.1"))
    let f = buildARPFrame(op: .reply,
                          senderMAC: senderMAC, senderIP: senderIP,
                          targetMAC: try #require(MACAddress("11:22:33:44:55:66")),
                          targetIP: try #require(IPv4Address("192.168.1.50")),
                          ethDst: try #require(MACAddress("11:22:33:44:55:66")),
                          ethSrc: senderMAC)
    let parsed = try #require(parseARPReply(f))
    #expect(parsed.0 == senderMAC)
    #expect(parsed.1 == senderIP)
}

@Test func parseRejectsRequest() throws {
    let f = buildARPFrame(op: .request,
                          senderMAC: try #require(MACAddress("aa:bb:cc:dd:ee:ff")),
                          senderIP: try #require(IPv4Address("192.168.1.1")),
                          targetMAC: .zero,
                          targetIP: try #require(IPv4Address("192.168.1.50")),
                          ethDst: .broadcast,
                          ethSrc: try #require(MACAddress("aa:bb:cc:dd:ee:ff")))
    #expect(parseARPReply(f) == nil)   // op=request игнорируется
}

// MARK: OUI

@Test func vendorLookup() throws {
    #expect(vendor(for: try #require(MACAddress("b8:27:eb:00:00:01"))) == "Raspberry Pi")
    #expect(vendor(for: try #require(MACAddress("3c:22:fb:aa:bb:cc"))) == "Apple")
    #expect(vendor(for: try #require(MACAddress("a0:0b:ba:11:22:33"))) == "Samsung Electronics")
    #expect(vendor(for: try #require(MACAddress("de:ad:be:ef:00:00"))) == "Unknown")
}

@Test func hostVendorProperty() throws {
    let host = Host(ip: try #require(IPv4Address("192.168.100.9")),
                    mac: try #require(MACAddress("3c:22:fb:00:00:01")))
    #expect(host.vendor == "Apple")
}
