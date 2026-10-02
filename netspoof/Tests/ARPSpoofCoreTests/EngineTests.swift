import Testing
import Foundation
@testable import ARPSpoofCore

// MARK: - Подставной спай вместо реального ARPSpoofer (без BPF/root)

private final class SpySpoofer: ARPSpoofing {
    let iface: InterfaceInfo
    init(iface: InterfaceInfo) { self.iface = iface }

    struct Poison: Equatable {
        let victimIP: IPv4Address, victimMAC: MACAddress
        let gatewayIP: IPv4Address, gatewayMAC: MACAddress
        let oneway: Bool
    }
    private(set) var poisons: [Poison] = []
    private(set) var restored: [MACAddress] = []
    private(set) var probeCount = 0

    func discoverHosts(duration: TimeInterval) -> [ARPSpoofCore.Host] { [] }
    func discoverHostsPassive(duration: TimeInterval) -> [ARPSpoofCore.Host] { [] }
    func resolveNames(for hosts: [ARPSpoofCore.Host], duration: TimeInterval) -> [MACAddress: String] { [:] }
    func probeSubnet() { probeCount += 1 }
    func poisonOnce(victimIP: IPv4Address, victimMAC: MACAddress,
                    gatewayIP: IPv4Address, gatewayMAC: MACAddress, oneway: Bool) {
        poisons.append(Poison(victimIP: victimIP, victimMAC: victimMAC,
                              gatewayIP: gatewayIP, gatewayMAC: gatewayMAC, oneway: oneway))
    }
    func restore(victimIP: IPv4Address, victimMAC: MACAddress,
                 gatewayIP: IPv4Address, gatewayMAC: MACAddress, times: Int) {
        restored.append(victimMAC)
    }
}

// MARK: - Фикстуры

private let selfMAC = MACAddress("aa:aa:aa:aa:aa:aa")!
private let selfIP = IPv4Address("192.168.1.100")!
private let gwMAC = MACAddress("11:11:11:11:11:11")!
private let gwIP = IPv4Address("192.168.1.1")!
private let victimMAC = MACAddress("cc:cc:cc:cc:cc:cc")!
private let victimIP = IPv4Address("192.168.1.42")!

private func makeEngine(oneway: Bool = false, passiveOnly: Bool = false)
    -> (SpoofEngine, SpySpoofer) {
    let iface = InterfaceInfo(name: "en0", mac: selfMAC, ip: selfIP, netmask: IPv4Address("255.255.255.0"))
    let spy = SpySpoofer(iface: iface)
    let engine = SpoofEngine(spoofer: spy, gatewayIP: gwIP, gatewayMAC: gwMAC, oneway: oneway)
    engine.passiveOnly = passiveOnly
    return (engine, spy)
}

/// ARP-кадр, где `senderMAC` утверждает, что он на `senderIP`.
private func senderFrame(mac: MACAddress, ip: IPv4Address) -> [UInt8] {
    buildARPFrame(op: .reply, senderMAC: mac, senderIP: ip,
                  targetMAC: selfMAC, targetIP: selfIP,
                  ethDst: selfMAC, ethSrc: mac)
}

// MARK: - start(): защита себя и шлюза

@Test func startIgnoresSelfAndGateway() {
    let (engine, _) = makeEngine()
    engine.start(selfMAC)   // травить себя нельзя
    engine.start(gwMAC)     // травить шлюз нельзя
    #expect(engine.active.isEmpty)

    engine.start(victimMAC)
    #expect(engine.active.contains(victimMAC))
}

// MARK: - probe: только в активном режиме и только для неизвестного IP

@Test func startProbesOnlyWhenNeeded() {
    // неизвестный IP + активный режим → один probe
    let (e1, s1) = makeEngine(passiveOnly: false)
    e1.start(victimMAC)
    #expect(s1.probeCount == 1)

    // неизвестный IP + ниндзя (passiveOnly) → никакого свипа
    let (e2, s2) = makeEngine(passiveOnly: true)
    e2.start(victimMAC)
    #expect(s2.probeCount == 0)

    // известный IP → probe не нужен
    let (e3, s3) = makeEngine(passiveOnly: false)
    e3.observe(ARPSpoofCore.Host(ip: victimIP, mac: victimMAC))
    e3.start(victimMAC)
    #expect(s3.probeCount == 0)
}

// MARK: - tick(): травит только активные с известным IP, пробрасывает oneway

@Test func tickPoisonsKnownTargetsOnly() {
    let (engine, spy) = makeEngine(oneway: false)
    engine.observe(ARPSpoofCore.Host(ip: victimIP, mac: victimMAC))
    engine.start(victimMAC)
    engine.tick()

    #expect(spy.poisons.count == 1)
    let p = spy.poisons[0]
    #expect(p.victimIP == victimIP)
    #expect(p.victimMAC == victimMAC)
    #expect(p.gatewayIP == gwIP)
    #expect(p.gatewayMAC == gwMAC)
    #expect(p.oneway == false)
}

@Test func tickPassesOnewayFlag() {
    let (engine, spy) = makeEngine(oneway: true)
    engine.observe(ARPSpoofCore.Host(ip: victimIP, mac: victimMAC))
    engine.start(victimMAC)
    engine.tick()
    #expect(spy.poisons.first?.oneway == true)
}

@Test func tickSkipsTargetsWithUnknownIP() {
    let (engine, spy) = makeEngine(passiveOnly: true)
    engine.start(victimMAC)      // IP неизвестен
    engine.tick()
    #expect(spy.poisons.isEmpty) // нечего травить — и НИЧЕГО не шлём
}

// MARK: - Блок-на-появление (ключевая регрессия)

@Test func blockOnAppearance() {
    let (engine, spy) = makeEngine(passiveOnly: true)
    engine.start(victimMAC)      // заблокирован, но сейчас оффлайн (IP неизвестен)
    engine.tick()
    #expect(spy.poisons.isEmpty) // пока не появился — не травим

    // устройство появилось: прилетел его ARP → связываем IP
    let moved = engine.ingest(senderFrame(mac: victimMAC, ip: victimIP))
    #expect(moved == victimMAC)

    engine.tick()                // теперь травим сразу
    #expect(spy.poisons.count == 1)
    #expect(spy.poisons[0].victimIP == victimIP)
}

// MARK: - Детект чужого ARP-спуфера

@Test func detectsGatewayImpersonationOnce() {
    let (engine, _) = makeEngine()
    var hits: [(MACAddress, IPv4Address)] = []
    engine.onSpoofDetected = { hits.append(($0, $1)) }

    let attacker = MACAddress("de:ad:be:ef:00:01")!
    _ = engine.ingest(senderFrame(mac: attacker, ip: gwIP))   // выдаёт себя за шлюз
    _ = engine.ingest(senderFrame(mac: attacker, ip: gwIP))   // повтор — не дублируем

    #expect(hits.count == 1)
    #expect(hits[0].0 == attacker)
    #expect(hits[0].1 == gwIP)
}

@Test func detectsSelfImpersonation() {
    let (engine, _) = makeEngine()
    var hits = 0
    engine.onSpoofDetected = { _, _ in hits += 1 }
    let attacker = MACAddress("de:ad:be:ef:00:02")!
    _ = engine.ingest(senderFrame(mac: attacker, ip: selfIP))  // выдаёт себя за НАС
    #expect(hits == 1)
}

@Test func doesNotDetectOurOwnOrLegitFrames() {
    let (engine, _) = makeEngine()
    var hits = 0
    engine.onSpoofDetected = { _, _ in hits += 1 }

    // наши собственные кадры травли (senderMAC == наш iface.mac) — не ложная тревога
    _ = engine.ingest(senderFrame(mac: selfMAC, ip: gwIP))
    // легитимный ARP от самого шлюза
    _ = engine.ingest(senderFrame(mac: gwMAC, ip: gwIP))
    // обычное устройство на своём IP
    _ = engine.ingest(senderFrame(mac: victimMAC, ip: victimIP))

    #expect(hits == 0)
}

// MARK: - ingest(): обновление связок и «переезд» цели

@Test func ingestTracksBindingChanges() {
    let (engine, _) = makeEngine()
    #expect(engine.ingest(senderFrame(mac: victimMAC, ip: victimIP)) == victimMAC) // новый
    #expect(engine.ingest(senderFrame(mac: victimMAC, ip: victimIP)) == nil)       // без изменений
    let newIP = IPv4Address("192.168.1.77")!
    #expect(engine.ingest(senderFrame(mac: victimMAC, ip: newIP)) == victimMAC)    // переезд
    #expect(engine.currentIP(of: victimMAC) == newIP)
}

// MARK: - stop/stopAll восстанавливают кэш

@Test func stopRestoresAndClears() {
    let (engine, spy) = makeEngine()
    engine.observe(ARPSpoofCore.Host(ip: victimIP, mac: victimMAC))
    engine.start(victimMAC)
    engine.stop(victimMAC)
    #expect(spy.restored == [victimMAC])
    #expect(engine.active.isEmpty)
}

@Test func stopAllRestoresEveryTarget() {
    let (engine, spy) = makeEngine()
    let m2 = MACAddress("dd:dd:dd:dd:dd:dd")!
    engine.observe(ARPSpoofCore.Host(ip: victimIP, mac: victimMAC))
    engine.observe(ARPSpoofCore.Host(ip: IPv4Address("192.168.1.43")!, mac: m2))
    engine.start(victimMAC); engine.start(m2)
    engine.stopAll()
    #expect(Set(spy.restored) == [victimMAC, m2])
    #expect(engine.active.isEmpty)
}

// MARK: - RateWindow: скользящее среднее

@Test func rateWindowAveragesOverWindow() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var w = RateWindow(window: 5, now: t0)
    let m = victimMAC
    let interest: Set<MACAddress> = [m]

    w.record([m: 1024], interest: interest, now: t0.addingTimeInterval(1)) // 1 KB за 1с
    #expect(abs((w.rates(interest: interest)[m] ?? -1) - 1.0) < 0.001)

    w.record([m: 2048], interest: interest, now: t0.addingTimeInterval(2)) // +2 KB за 1с
    // среднее: 3072 байт / 2с = 1.5 KB/s
    #expect(abs((w.rates(interest: interest)[m] ?? -1) - 1.5) < 0.001)
}

@Test func rateWindowAgesOutOldSamples() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var w = RateWindow(window: 3, now: t0)
    let m = victimMAC
    let interest: Set<MACAddress> = [m]

    w.record([m: 100_000], interest: interest, now: t0.addingTimeInterval(1)) // всплеск
    // тишина в течение окна
    for s in 2...6 { w.record([m: 0], interest: interest, now: t0.addingTimeInterval(Double(s))) }
    // старый всплеск выпал из окна (3с) → скорость упала почти до нуля
    #expect((w.rates(interest: interest)[m] ?? 999) < 0.01)
}

@Test func rateWindowIdleIsZero() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var w = RateWindow(window: 5, now: t0)
    let m = victimMAC
    w.record([:], interest: [m], now: t0.addingTimeInterval(1))
    #expect((w.rates(interest: [m])[m] ?? -1) == 0)
}

@Test func rateWindowWeightsByInterval() {
    // Регрессия: усреднение взвешено по dt, а не «1 сэмпл = 1 секунда».
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var w = RateWindow(window: 10, now: t0)
    let m = victimMAC
    // 4096 байт накопилось за 4-секундный интервал → 1 KB/s, а не 4.
    w.record([m: 4096], interest: [m], now: t0.addingTimeInterval(4))
    #expect(abs((w.rates(interest: [m])[m] ?? -1) - 1.0) < 0.001)
}

@Test func rateWindowForgetsDevicesLeavingInterest() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var w = RateWindow(window: 5, now: t0)
    let m = victimMAC
    w.record([m: 4096], interest: [m], now: t0.addingTimeInterval(1))
    // интерес сменился — m больше не отслеживаем
    let other = MACAddress("ee:ee:ee:ee:ee:ee")!
    w.record([:], interest: [other], now: t0.addingTimeInterval(2))
    #expect(w.rates(interest: [m])[m] == 0) // забыт, не тянет старые байты
}

// MARK: - MACMasker.plausible(): правдоподобный, не «явно рандомный»

@Test func plausibleMACInvariants() {
    for _ in 0..<500 {
        let m = MACMasker.plausible()
        #expect(m.bytes.count == 6)
        #expect(m.bytes[0] & 0x01 == 0) // юникаст (не мультикаст)
        #expect(m.bytes[0] & 0x02 == 0) // НЕ locally-administered — выглядит как вендор
    }
}

// MARK: - ForwardingControl (с инъекцией sysctl)

@Test func forwardingCutForcesOff() {
    var fwd = true   // кто-то включил форвардинг до нас
    let fc = ForwardingControl(cutMode: true, read: { fwd }, write: { fwd = $0; return true })
    fc.apply(hasActive: true)
    #expect(fwd == false)          // cut → принудительно выключен
    #expect(fc.isOn == false)
}

@Test func forwardingInterceptTogglesWithTargets() {
    var fwd = false
    let fc = ForwardingControl(cutMode: false, read: { fwd }, write: { fwd = $0; return true })
    fc.apply(hasActive: true)      // intercept + есть цели → включаем
    #expect(fwd == true)
    #expect(fc.enabledByUs == true)
    fc.apply(hasActive: false)     // целей нет → выключаем (мы же включали)
    #expect(fwd == false)
    #expect(fc.enabledByUs == false)
}

@Test func forwardingLeavesForeignForwardingAlone() {
    var fwd = true                 // форвардинг включён НЕ нами
    let fc = ForwardingControl(cutMode: false, read: { fwd }, write: { fwd = $0; return true })
    fc.apply(hasActive: false)
    #expect(fwd == true)           // чужой форвардинг не трогаем
}

@Test func forwardingSwitchToCutKillsEvenForeign() {
    var fwd = true
    let fc = ForwardingControl(cutMode: false, read: { fwd }, write: { fwd = $0; return true })
    fc.cutMode = true
    fc.apply(hasActive: true)
    #expect(fwd == false)          // переключение в cut гасит даже чужой форвардинг
}
