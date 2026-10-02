#include "cbpf.h"

#include <net/bpf.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <sys/sysctl.h>
#include <stdlib.h>
#include <string.h>
#include <libproc.h>
#include <signal.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_media.h>

int cbpf_set_interface(int fd, const char *ifname) {
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, sizeof(ifr.ifr_name) - 1);
    return ioctl(fd, BIOCSETIF, &ifr);
}

int cbpf_set_immediate(int fd, int on) {
    return ioctl(fd, BIOCIMMEDIATE, &on);
}

int cbpf_set_header_complete(int fd, int on) {
    return ioctl(fd, BIOCSHDRCMPLT, &on);
}

int cbpf_get_blen(int fd, unsigned int *len) {
    return ioctl(fd, BIOCGBLEN, len);
}

int cbpf_set_blen(int fd, unsigned int len) {
    return ioctl(fd, BIOCSBLEN, &len);
}

int cbpf_flush(int fd) {
    return ioctl(fd, BIOCFLUSH, (void *)0);
}

int cbpf_set_arp_filter(int fd) {
    // Классический фильтр: взять ethertype (offset 12, halfword),
    // если == 0x0806 — принять кадр целиком, иначе отбросить.
    struct bpf_insn insns[] = {
        BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 12),
        BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0x0806, 0, 1),
        BPF_STMT(BPF_RET + BPF_K, 0x40000),
        BPF_STMT(BPF_RET + BPF_K, 0),
    };
    struct bpf_program prog;
    prog.bf_len = sizeof(insns) / sizeof(insns[0]);
    prog.bf_insns = insns;
    return ioctl(fd, BIOCSETF, &prog);
}

int cbpf_set_count_filter(int fd) {
    // Для монитора трафика: принять ВСЕ кадры, но усечь до 64 байт — хватает
    // Ethernet-заголовка (src/dst MAC). Истинную длину пакета берём из
    // bh_datalen, поэтому учёт байт точный, а копируем лишь 64 байта/пакет.
    struct bpf_insn insns[] = {
        BPF_STMT(BPF_RET + BPF_K, 64),
    };
    struct bpf_program prog;
    prog.bf_len = sizeof(insns) / sizeof(insns[0]);
    prog.bf_insns = insns;
    return ioctl(fd, BIOCSETF, &prog);
}

unsigned int cbpf_hdr_len(const void *p) {
    const struct bpf_hdr *bh = (const struct bpf_hdr *)p;
    return bh->bh_hdrlen;
}

unsigned int cbpf_caplen(const void *p) {
    const struct bpf_hdr *bh = (const struct bpf_hdr *)p;
    return bh->bh_caplen;
}

unsigned int cbpf_datalen(const void *p) {
    const struct bpf_hdr *bh = (const struct bpf_hdr *)p;
    return bh->bh_datalen; // истинная длина пакета до усечения
}

unsigned int cbpf_wordalign(unsigned int x) {
    return BPF_WORDALIGN(x);
}

int cbpf_sdl_mac(const struct sockaddr *sa, unsigned char out[6]) {
    if (sa->sa_family != AF_LINK) return -1;
    const struct sockaddr_dl *sdl = (const struct sockaddr_dl *)sa;
    if (sdl->sdl_alen != 6) return -1;
    memcpy(out, LLADDR(sdl), 6);
    return 0;
}

/* Выравнивание sockaddr внутри route-сообщения (как SA_SIZE на BSD). */
#define CBPF_RT_ROUNDUP(a) \
    ((a) > 0 ? (1 + (((a) - 1) | (sizeof(uint32_t) - 1))) : sizeof(uint32_t))

int cbpf_default_gateway(unsigned char out[4]) {
    int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0 };
    size_t len = 0;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0 || len == 0) return -1;

    char *buf = (char *)malloc(len);
    if (!buf) return -1;
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) { free(buf); return -1; }

    char *lim = buf + len;
    int found = -1;
    for (char *next = buf; next < lim; ) {
        struct rt_msghdr *rtm = (struct rt_msghdr *)next;
        if (rtm->rtm_msglen == 0) break;
        next += rtm->rtm_msglen;

        if (rtm->rtm_version != RTM_VERSION) continue;
        if (!(rtm->rtm_flags & RTF_GATEWAY)) continue;

        /* Разложить sockaddr'ы по маске rtm_addrs в порядке RTAX_*. */
        struct sockaddr *addrs[RTAX_MAX];
        memset(addrs, 0, sizeof(addrs));
        char *cp = (char *)(rtm + 1);
        for (int i = 0; i < RTAX_MAX; i++) {
            if (rtm->rtm_addrs & (1 << i)) {
                struct sockaddr *sa = (struct sockaddr *)cp;
                addrs[i] = sa;
                cp += CBPF_RT_ROUNDUP(sa->sa_len);
            }
        }

        struct sockaddr *d = addrs[RTAX_DST];
        struct sockaddr *g = addrs[RTAX_GATEWAY];
        if (!d || !g) continue;
        if (d->sa_family != AF_INET || g->sa_family != AF_INET) continue;

        /* Маршрут по умолчанию: dst == 0.0.0.0 */
        struct sockaddr_in *din = (struct sockaddr_in *)d;
        if (din->sin_addr.s_addr != 0) continue;

        struct sockaddr_in *gin = (struct sockaddr_in *)g;
        memcpy(out, &gin->sin_addr.s_addr, 4);
        found = 0;
        break;
    }

    free(buf);
    return found;
}

int cbpf_arp_cache(struct cbpf_arp_entry *out, int max) {
    // Дамп ARP-кэша: маршруты AF_INET с флагом RTF_LLINFO (link-layer info).
    // Пассивно — только читаем системную таблицу, ничего не отправляем.
    int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO };
    size_t len = 0;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0 || len == 0) return 0;

    char *buf = (char *)malloc(len);
    if (!buf) return 0;
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) { free(buf); return 0; }

    char *lim = buf + len;
    int count = 0;
    for (char *next = buf; next < lim && count < max; ) {
        struct rt_msghdr *rtm = (struct rt_msghdr *)next;
        if (rtm->rtm_msglen == 0) break;
        next += rtm->rtm_msglen;

        /* Сразу за заголовком — dst (sockaddr_in), затем gateway (sockaddr_dl). */
        struct sockaddr_in *sin = (struct sockaddr_in *)(rtm + 1);
        struct sockaddr_dl *sdl =
            (struct sockaddr_dl *)((char *)sin + CBPF_RT_ROUNDUP(sin->sin_len));

        if (sin->sin_family != AF_INET) continue;
        if (sdl->sdl_family != AF_LINK || sdl->sdl_alen != 6) continue; /* без MAC — пропуск */

        memcpy(out[count].ip, &sin->sin_addr.s_addr, 4);
        memcpy(out[count].mac, LLADDR(sdl), 6);
        count++;
    }

    free(buf);
    return count;
}

int cbpf_is_wifi(const char *ifname) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) return 0;
    struct ifmediareq ifmr;
    memset(&ifmr, 0, sizeof(ifmr));
    strncpy(ifmr.ifm_name, ifname, sizeof(ifmr.ifm_name) - 1);
    int wifi = 0;
    if (ioctl(s, SIOCGIFMEDIA, &ifmr) == 0) {
        wifi = (IFM_TYPE(ifmr.ifm_current) == IFM_IEEE80211) ? 1 : 0;
    }
    close(s);
    return wifi;
}

int cbpf_get_mac(const char *ifname, unsigned char out[6]) {
    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) != 0) return -1;
    int rc = -1;
    for (struct ifaddrs *ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK &&
            strcmp(ifa->ifa_name, ifname) == 0) {
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            if (sdl->sdl_alen == 6) { memcpy(out, LLADDR(sdl), 6); rc = 0; break; }
        }
    }
    freeifaddrs(ifap);
    return rc;
}

int cbpf_set_mac(const char *ifname, const unsigned char mac[6]) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) return -1;

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, sizeof(ifr.ifr_name) - 1);

    // Wi-Fi не даёт менять MAC «на горячую» — сначала опускаем интерфейс.
    if (ioctl(s, SIOCGIFFLAGS, &ifr) < 0) { close(s); return -1; }
    short saved = ifr.ifr_flags;
    ifr.ifr_flags = saved & ~IFF_UP;
    ioctl(s, SIOCSIFFLAGS, &ifr);
    usleep(300000);

    // Собственно смена аппаратного адреса.
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, sizeof(ifr.ifr_name) - 1);
    ifr.ifr_addr.sa_len = 6;
    ifr.ifr_addr.sa_family = AF_LINK;
    memcpy(ifr.ifr_addr.sa_data, mac, 6);
    int rc = ioctl(s, SIOCSIFLLADDR, &ifr);

    // Поднимаем интерфейс обратно в любом случае (даже если смена не удалась).
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, sizeof(ifr.ifr_name) - 1);
    if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) {
        ifr.ifr_flags = ifr.ifr_flags | IFF_UP;
        ioctl(s, SIOCSIFFLAGS, &ifr);
    }
    close(s);
    return rc;
}

void cbpf_kill_other_netspoof(void) {
    pid_t self = getpid();
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return;

    int cap = bytes + 16 * (int)sizeof(pid_t);
    pid_t *pids = (pid_t *)malloc(cap);
    if (!pids) return;

    int got = proc_listpids(PROC_ALL_PIDS, 0, pids, cap);
    int count = got / (int)sizeof(pid_t);
    char name[256];
    for (int i = 0; i < count; i++) {
        pid_t p = pids[i];
        if (p <= 0 || p == self) continue;
        name[0] = 0;
        if (proc_name(p, name, sizeof(name)) > 0 && strcmp(name, "netspoof") == 0) {
            kill(p, SIGKILL);
        }
    }
    free(pids);
}
