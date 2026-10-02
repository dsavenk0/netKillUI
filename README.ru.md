# netspoof

Нативный аналог `arpspoof` (из dsniff) для macOS на Swift. Делает ARP cache
poisoning через прямую инъекцию Ethernet-кадров в `/dev/bpf*` (Berkeley Packet
Filter) — без сторонних зависимостей.

> ## ⚠️ Предупреждение об использовании
>
> **netspoof / netKillUI — инструмент для авторизованного тестирования.**
> ARP cache poisoning перехватывает и может разрывать трафик в локальной сети.
>
> - Применяйте **только** в сети, которой владеете, или имея **письменное
>   разрешение** её владельца.
> - Использование против чужих устройств или сетей без согласия **незаконно**
>   в большинстве юрисдикций и может повлечь гражданскую и уголовную
>   ответственность.
> - Вся ответственность за использование лежит на вас. Авторы не отвечают за
>   любой ущерб или противоправное применение (см. также `LICENSE`).
>
> Запуская этот инструмент, вы подтверждаете, что действуете законно и с
> разрешения владельца сети.

## Сборка

```sh
cd netspoof
swift build -c release
# бинарь: .build/release/netspoof
```

## Запуск

Нужен root (доступ к `/dev/bpf*` и к `net.inet.ip.forwarding`).

Скан подсети — инвентаризация живых хостов:

```sh
sudo .build/release/netspoof scan -i en0
```

MITM одной цели (трафик идёт прозрачно через ваш Mac, т.к. включается
IP forwarding):

```sh
sudo .build/release/netspoof spoof -i en0 -t 192.168.1.42
```

Опции `spoof`:

| Опция              | Назначение                                              |
|--------------------|---------------------------------------------------------|
| `-g <ip>`          | IP шлюза (по умолчанию — маршрут по умолчанию)           |
| `--oneway`         | травить только цель, не шлюз                             |
| `--interval <ms>`  | период переотправки ARP-reply (по умолчанию 2000)       |
| `--no-forward`     | не включать ip forwarding (связь цели прервётся)         |

`Ctrl-C` корректно восстанавливает ARP-кэш обеих сторон и выключает forwarding.

## Как это устроено

```
CBPF (C-shim)        ioctl'ы BPF (BIOCSETIF/BIOCIMMEDIATE/BIOCSETF…),
                     которые не импортируются в Swift из-за макросов _IOW.
ARPSpoofCore
  MACAddress/IPv4    типы адресов + арифметика по подсети
  NetworkInterface   getifaddrs → MAC/IP/маска интерфейса
  RouteTable         шлюз по умолчанию + sysctl ip-forwarding
  ARPPacket          сборка/разбор Ethernet+ARP кадров
  BPFDevice          open /dev/bpfN, inject (write) и capture (poll+read)
  ARPSpoofer         resolveMAC, scan, poisonOnce, restore
netspoof (CLI)       разбор аргументов, цикл, обработка сигналов
```

Механика poisoning: цели шлётся ARP-reply «`gatewayIP` находится на моём MAC»,
шлюзу — «`targetIP` на моём MAC». Обе стороны обновляют кэш, трафик идёт через
нас. С включённым `ip.forwarding` мы прозрачно пересылаем его дальше (MITM); без
него — связь цели рвётся.

## Нативная GUI-обёртка (следующий шаг)

Ядро (`ARPSpoofCore`) переиспользуется как есть. Для .app на SwiftUI нужен
стандартный для macOS паттерн разделения привилегий:

- **SwiftUI-фронтенд** (обычный user-процесс): список устройств из `scan`,
  тумблеры по целям, статус.
- **Privileged helper** (root-демон) — ставится через `SMAppService`
  (`.daemon`, macOS 13+) или легаси `SMJobBless`. Только он держит BPF и гоняет
  цикл спуфинга.
- **XPC** между ними: фронт шлёт команды `startSpoof(target:)` / `stop` /
  `scan`, helper отвечает событиями.

Helper линкуется с тем же `ARPSpoofCore`. Фронтенд в sandbox'е ядро не трогает.
Для распространения helper и app нужно подписать Developer ID.
