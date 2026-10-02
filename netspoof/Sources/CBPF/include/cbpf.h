#ifndef CBPF_H
#define CBPF_H

#include <sys/socket.h>

// Привязать открытый /dev/bpfN к сетевому интерфейсу (BIOCSETIF).
int cbpf_set_interface(int fd, const char *ifname);

// Immediate mode: read() возвращается сразу по приходу пакета (BIOCIMMEDIATE).
int cbpf_set_immediate(int fd, int on);

// Мы сами формируем полный link-layer заголовок (BIOCSHDRCMPLT).
int cbpf_set_header_complete(int fd, int on);

// Размер буфера чтения BPF.
int cbpf_get_blen(int fd, unsigned int *len);
int cbpf_set_blen(int fd, unsigned int len);

int cbpf_flush(int fd);

// Установить фильтр "только ARP" (ethertype 0x0806), чтобы не захватывать
// весь трафик интерфейса.
int cbpf_set_arp_filter(int fd);

// Фильтр монитора трафика: принять все кадры, усечь до 64 байт (учёт байт
// идёт по bh_datalen, копируется лишь заголовок).
int cbpf_set_count_filter(int fd);

// IPv4-адрес шлюза по умолчанию через PF_ROUTE/NET_RT_DUMP (без подпроцессов).
// Пишет 4 байта в out, 0 — успех, -1 — не найдено/ошибка.
int cbpf_default_gateway(unsigned char out[4]);

// Одна запись ARP-кэша: IPv4 + MAC.
struct cbpf_arp_entry { unsigned char ip[4]; unsigned char mac[6]; };

// Прочитать ARP-кэш ОС (sysctl NET_RT_FLAGS/RTF_LLINFO) — пассивно, без единого
// отправленного пакета. Заполняет до max записей, возвращает их число.
int cbpf_arp_cache(struct cbpf_arp_entry *out, int max);

// Завершить все другие процессы с именем "netspoof" (кроме себя).
// Единственный экземпляр демона — без внешнего pkill и само-ловушек.
void cbpf_kill_other_netspoof(void);

// Прочитать/сменить аппаратный MAC интерфейса. set делает down→lladdr→up
// (Wi-Fi не меняет MAC «на горячую»). 0 — успех. Смена может не закрепиться
// на части систем — вызывающий обязан перечитать get и проверить.
int cbpf_get_mac(const char *ifname, unsigned char out[6]);
int cbpf_set_mac(const char *ifname, const unsigned char mac[6]);

// Интерфейс — это Wi-Fi (IFM_IEEE80211)? На встроенном Wi-Fi Apple Silicon
// смена MAC не закрепляется, поэтому там её даже не пытаемся делать.
int cbpf_is_wifi(const char *ifname);

// Разбор заголовка bpf_hdr, лежащего по указателю p.
unsigned int cbpf_hdr_len(const void *p);   // bh_hdrlen
unsigned int cbpf_caplen(const void *p);     // bh_caplen
unsigned int cbpf_datalen(const void *p);    // bh_datalen (истинная длина)
unsigned int cbpf_wordalign(unsigned int x); // BPF_WORDALIGN

// Извлечь MAC (6 байт) из sockaddr_dl (AF_LINK). 0 — успех.
int cbpf_sdl_mac(const struct sockaddr *sa, unsigned char out[6]);

#endif
