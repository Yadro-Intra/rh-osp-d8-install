/*
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Stolen here: https://gist.github.com/austinmarton/2862515
 */

#include <unistd.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <linux/udp.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/ether.h>
#include <signal.h>
#include <ctype.h>
#include <sys/time.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/ip_icmp.h>

#define DEST_MAC0	0x00
#define DEST_MAC1	0x00
#define DEST_MAC2	0x00
#define DEST_MAC3	0x00
#define DEST_MAC4	0x00
#define DEST_MAC5	0x00

#define ETHER_TYPE	0x0800

#define DEFAULT_IF	"eth0"
#define BUF_SIZ		4096

static struct {
	int auto_exclude;
	int ifName_set;
	int pxe_only;
	int promisc_mode;
	int dump_packet;
	int max_packets;
	int interesting;
	int only;
	int no_srv;
} parm = {
	.auto_exclude = 1,
};


typedef uint32_t ipv4_addr_t;
typedef char eth_mac_t[6];

#define MAX_BAD_IP 32

struct ipv4_cidr {
	ipv4_addr_t ip;
	int bits;
};

struct {
	char ifName[IFNAMSIZ];

	uint64_t total_count;
	uint64_t total_printed;
	struct timeval t0;

	int do_the_job;

	short int saved_ifru_flags;
	int restore_flags;

	ipv4_addr_t local_ip;
	eth_mac_t local_mac;

	char local_ip_str[INET6_ADDRSTRLEN];
	char local_mac_str[32];

	struct ipv4_cidr ignored_ip[MAX_BAD_IP];
	int ignored_ip_count;

	eth_mac_t ignored_mac[MAX_BAD_IP];
	int ignored_mac_count;

	struct ipv4_cidr tracked_ip[MAX_BAD_IP];
	int tracked_ip_count;

	eth_mac_t tracked_mac[MAX_BAD_IP];
	int tracked_mac_count;

	unsigned short ignored_ports[MAX_BAD_IP];
	int ignored_port_count;
} global = {
	.ifName = DEFAULT_IF,
	.ignored_mac_count = 1, /* null MAC is always ignored */

};

const eth_mac_t broadcast_mac = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

static int a2i(char *s)
{
	char *p;
	long int r;

	errno = 0;
	r = strtol(s, &p, 10);
	if (errno) {
		perror("strtol");
		exit(EXIT_FAILURE);
	}
	if (r == 0L && p == s) {
		fprintf(stderr, "Invalid decimal value '%s'.\n", s);
		exit(EXIT_FAILURE);
	}

	return (int) r;
}

static void ipv4_to_str(ipv4_addr_t ip, char *s, size_t size)
{
	struct sockaddr_storage their_addr = {};

	((struct sockaddr_in *)&their_addr)->sin_addr.s_addr = ip;
	inet_ntop(AF_INET, &((struct sockaddr_in*)&their_addr)->sin_addr, s, size);
}

static char *ipv4_as_str(ipv4_addr_t ip)
{
	static char tmp[INET6_ADDRSTRLEN];

	ipv4_to_str(ip, tmp, sizeof(tmp)-1);
	return tmp;
}

static inline int ip_in_list(ipv4_addr_t ip, const struct ipv4_cidr *list, int list_size)
{
	int i;

	for (i = 0; i < list_size; i++) {
		uint32_t a = ip << (32 - list[i].bits);
		uint32_t b = list[i].ip << (32 - list[i].bits);

		if (a == b)
			return 1;
	}
	return 0;
}

static void add_ip_to_list(const char *ip, struct ipv4_cidr *list, int *list_size)
{
	char tmp[INET6_ADDRSTRLEN], *p;
	ipv4_addr_t addr;
	int ret;

	if (*list_size >= MAX_BAD_IP)
		return;

	strncpy(tmp, ip, sizeof(tmp)-1);
	p = strchr(tmp, '/');
	if (p)
		*p++ = '\0';

	ret = inet_pton(AF_INET, tmp, &addr);

	switch (ret) {
	case 1:
		list[*list_size].bits = p ? a2i(p) : 32;
		list[*list_size].ip = addr;
		(*list_size)++;
		return;
	case 0:
		fprintf(stderr, "Error: '%s' is not valid IPv4 address\n", ip);
		exit(EXIT_FAILURE);
	case -1:
		perror("inet_pton");
		exit(EXIT_FAILURE);
	default:
		fprintf(stderr, "Error: inet_pton returned %d\n", ret);
		exit(EXIT_FAILURE);
	}
}

static void ignore_ports(char *arg)
{
	char *q, *p = arg;

	while (global.ignored_port_count < MAX_BAD_IP) {
		long int r;

		errno = 0;
		r = strtol(p, &q, 10);

		if (errno || q == p) {
			/* service name? */
			struct servent *se;
			q = strchr(p, ',');
			if (q)
				*q = '\0';
			se = getservbyname(p, "tcp");
			se = se ? se : getservbyname(p, "udp");
			if (!se) {
				fprintf(stderr, "Unknown service \"%s\".\n", p);
				exit(EXIT_FAILURE);
			}
			if (q)
				*q = ',';
			r = ntohs(se->s_port);
		}

		/* r = port number */
		global.ignored_ports[global.ignored_port_count++] = htons(r);
		fprintf(stderr, "\tport %lu\n", r);

		if (!q || !*q) break;

		if (*q == ',') *q++ = '\0';
		p = q;
	}
}

static int ignored_port(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));
	const struct udphdr *udp = (struct udphdr *)
		(packet + sizeof(struct iphdr) + sizeof(struct ether_header));
	int i;

	if (ip->protocol != IPPROTO_TCP && ip->protocol != IPPROTO_UDP)
		return 0;

	for (i = 0; i < global.ignored_port_count; i++) {
		if (	global.ignored_ports[i] == udp->source ||
			global.ignored_ports[i] == udp->dest)
			return 1;
	}
	return 0;
}

static inline void add_ignored_ip(const char *ip)
{
	add_ip_to_list(ip, global.ignored_ip, &global.ignored_ip_count);
	fprintf(stderr, "Will ignore '%s/%d'\n",
		ipv4_as_str(global.ignored_ip[global.ignored_ip_count - 1].ip),
		global.ignored_ip[global.ignored_ip_count - 1].bits);
}

static inline int is_ignored_ip(ipv4_addr_t ip)
{
	return ip_in_list(ip, global.ignored_ip, global.ignored_ip_count);
}

static inline void add_tracked_ip(const char *ip)
{
	add_ip_to_list(ip, global.tracked_ip, &global.tracked_ip_count);
	fprintf(stderr, "Will watch '%s/%d'\n",
		ipv4_as_str(global.tracked_ip[global.tracked_ip_count - 1].ip),
		global.tracked_ip[global.tracked_ip_count - 1].bits);
}

static inline int is_tracked_ip(ipv4_addr_t ip)
{
	return ip_in_list(ip, global.tracked_ip, global.tracked_ip_count);
}

static inline int mac_equal(const void *mac1, const void *mac2)
{
	const uint16_t *p1 = mac1;
	const uint16_t *p2 = mac2;

	return	p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
}

static inline int mac_starts_with(const void *mac1, const uint8_t mac2[], size_t octets)
{
	const uint8_t *mac = mac1;
	size_t i;

	for (i = 0; i < octets; i++) {
		if (mac[i] != mac2[i])
			return 0;
	}
	return 1;
}

/* parse hex-colon 6-bytes Ethernet MAC address notation */
static int eth_pton(const char *mac, eth_mac_t addr)
{
	int i = 0, n = 0, octet = 0;

	for (;;) {
		int c = mac[i++];

		if (c == '\0') {
			if (n == 5) {
				addr[n] = octet;
				return 1;
			}
			return 0;
		}
		if (c == ':') {
			if (n > 5)
				return 0;
			addr[n++] = octet;
			octet = 0;
			continue;
		}
		if (isxdigit(c)) {
			octet = (octet << 4) | (c - (isdigit(c) ? '0' : 'a'));
			if (octet < 0 || octet > 255)
				return 0;
			continue;
		}
		return 0;
	}
}

static void add_ignored_mac(const char *mac)
{
	eth_mac_t addr;
	int ret = eth_pton(mac, addr);

	if (global.ignored_mac_count >= MAX_BAD_IP)
		return;

	switch (ret) {
	case 1:
		memcpy(global.ignored_mac[global.ignored_mac_count++], addr, sizeof(addr));
		return;
	case 0:
		fprintf(stderr, "Error: '%s' is not a valid Ethernet MAC address\n", mac);
		exit(EXIT_FAILURE);
	case -1:
		perror("inet_pton");
		exit(EXIT_FAILURE);
	default:
		fprintf(stderr, "Error: inet_pton returned %d\n", ret);
		exit(EXIT_FAILURE);
	}
}

static inline int is_ignored_mac(const void *mac)
{
	int i;

	for (i = 0; i < global.ignored_mac_count; i++) {
		if (mac_equal(mac, global.ignored_mac[i]))
			return 1;
	}
	return 0;
}

static void add_tracked_mac(const char *mac)
{
	eth_mac_t addr;
	int ret = eth_pton(mac, addr);

	if (global.tracked_mac_count >= MAX_BAD_IP)
		return;

	switch (ret) {
	case 1:
		memcpy(global.tracked_mac[global.tracked_mac_count++], addr, sizeof(addr));
		return;
	case 0:
		fprintf(stderr, "Error: '%s' is not a valid Ethernet MAC address\n", mac);
		exit(EXIT_FAILURE);
	case -1:
		perror("inet_pton");
		exit(EXIT_FAILURE);
	default:
		fprintf(stderr, "Error: inet_pton returned %d\n", ret);
		exit(EXIT_FAILURE);
	}
}

static inline int is_mcast_mac(const void *mac)
{
	static const uint8_t mcast_pfx1[] = { 0x01, 0x80, 0xc2 };
	static const uint8_t mcast_pfx2[] = { 0x01, 0x00, 0x5e };

	return	mac_starts_with(mac, mcast_pfx1, 3) ||
		mac_starts_with(mac, mcast_pfx2, 3);
}

static inline int is_mcast_eth(const void *packet)
{
	const struct ether_header *eh = packet;

	return	is_mcast_mac(eh->ether_dhost);
}

static inline int is_tracked_mac(const void *mac)
{
	int i;

	if (parm.interesting && is_mcast_mac(mac))
		return 1;

	for (i = 0; i < global.tracked_mac_count; i++) {
		if (mac_equal(mac, global.tracked_mac[i]))
			return 1;
	}
	return 0;
}

const uint16_t lldp_type = 0x88cc;

const eth_mac_t lldp_mac1 = { 0x01, 0x80, 0xc2, 0x00, 0x00, 0x00 };
const eth_mac_t lldp_mac2 = { 0x01, 0x80, 0xc2, 0x00, 0x00, 0x03 };
const eth_mac_t lldp_mac3 = { 0x01, 0x80, 0xc2, 0x00, 0x00, 0x0e };

static int is_lldp(const void *packet)
{
	const struct ether_header *eh = packet;

	return eh->ether_type == lldp_type ||
		mac_equal(eh->ether_dhost, lldp_mac1) ||
		mac_equal(eh->ether_dhost, lldp_mac2) ||
		mac_equal(eh->ether_dhost, lldp_mac3);
}

const eth_mac_t bpdu_mac1 = { 0x01, 0x80, 0xc2, 0x00, 0x00, 0x00 };
const eth_mac_t bpdu_mac2 = { 0x01, 0x00, 0x0c, 0xcc, 0xcc, 0xcd };

struct bpdu {
	uint16_t protocol; /* 0 = IEEE 802.1D */
	uint8_t version_id; /* 0=Config/TCN, 2=RST, 3=MSTP, 4=SPT */
	uint8_t type; /* 0=Config, 0x80=TCN, 0x02=RST */
	/* TCNs have no following fields */
	union {
		uint8_t value;
		struct {
			uint8_t tc : 1;
			uint8_t proposal : 1;
			uint8_t port_role : 2;
			uint8_t learning : 1;
			uint8_t forwarding : 1;
			uint8_t agreement : 1;
			uint8_t tc_ack : 1;
		} bit;
	} flags;
	union {
		uint64_t value;
		struct {
			uint64_t prio : 4;
			uint64_t sysidx : 12;
			uint64_t mac : 48;
		} root_bridge;
	} root_id;
	uint32_t root_path_cost;
	union {
		uint64_t value;
		struct {
			uint64_t prio : 4;
			uint64_t sysidx : 12;
			uint64_t mac : 48;
		} root_bridge;
	} bridge_id;
	uint16_t port_id;
	uint16_t msg_age;
	uint16_t max_age;
	uint16_t hello_time;
	uint16_t fwd_delay;
	uint8_t ver1_len;
	uint16_t ver3_len;
};

static int is_bpdu(const void *packet)
{
	const struct ether_header *eh = packet;

	return mac_equal(eh->ether_dhost, bpdu_mac1) ||
		mac_equal(eh->ether_dhost, bpdu_mac2);
}

static inline int tracked_packet(const void *packet)
{
	const struct ether_header *eh = packet;
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	return	is_tracked_ip(ip->saddr) || is_tracked_mac(eh->ether_shost) ||
		is_tracked_ip(ip->daddr) || is_tracked_mac(eh->ether_dhost);
}

static int is_UPnP_ssdp(const void *packet);

static inline int ignored_packet(const void *packet)
{
	const struct ether_header *eh = packet;
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	if (tracked_packet(packet))
		return 0;

	if (parm.interesting) {
		if (is_UPnP_ssdp(packet))
			return 1;
	}

	return	is_ignored_ip(ip->saddr) || is_ignored_mac(eh->ether_shost) ||
		is_ignored_ip(ip->daddr) || is_ignored_mac(eh->ether_dhost);
}

static inline int match_cidr(ipv4_addr_t ip, uint8_t o1, uint8_t o2, uint8_t o3, uint8_t o4, int bits)
{
	ipv4_addr_t mask = htonl((o1 << 24) | (o2 << 16) | (o3 << 8) | o4);

	bits = 32 - bits;

	return (ip << bits) == (mask << bits);
}

static inline int ipv4_equal(ipv4_addr_t ip, uint8_t o1, uint8_t o2, uint8_t o3, uint8_t o4)
{
	ipv4_addr_t test = htonl((o1 << 24) | (o2 << 16) | (o3 << 8) | o4);

	return ip == test;
}

static int is_mcast_IPv4(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	/* https://tools.ietf.org/html/draft-ietf-mboned-ipv4-mcast-unusable-01 */
	if (match_cidr(ip->daddr, 224,0,0,0, 4)) /* 224/4 */
		return 1;
	return 0;
}

static int is_pvt_IPv4(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	/* RFC 1918 */
	if (	match_cidr(ip->saddr, 10,0,0,0, 8)	/* 10.0.0.0/8 */ ||
		match_cidr(ip->saddr, 172,16,0,0, 12)	/* 172.16.0.0/12 */ ||
		match_cidr(ip->saddr, 192,168,0,0, 16)	/* 192.168.0.0/16 */
	)
		return 1;
	return 0;
}

static int is_ll_IPv4(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	/* https://tools.ietf.org/html/draft-ietf-mboned-ipv4-mcast-unusable-01 */
	if (	(ip->saddr == 0)			/* 0.0.0.0/0 */ ||
		match_cidr(ip->saddr, 196,254,0,0, 16)	/* 196.254.0.0/16 */
	)
		return 1;
	return 0;
}

static int is_loopback_IPv4(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	/* https://tools.ietf.org/html/draft-ietf-mboned-ipv4-mcast-unusable-01 */
	if (match_cidr(ip->saddr, 127,0,0,0, 8))	/* 127.0.0.0/8 */
		return 1;
	return 0;
}

static int is_doc_IPv4(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	/* https://tools.ietf.org/html/draft-ietf-mboned-ipv4-mcast-unusable-01 */
	if (match_cidr(ip->saddr, 192,0,2,0, 24))	/* 192.0.2.0/24 */
		return 1;
	return 0;
}

static inline int is_pxe(const void *packet)
{
	const struct ether_header *eh = packet;
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));
	
	return (ip->saddr == INADDR_ANY &&
		ip->daddr == INADDR_BROADCAST &&
		mac_equal(eh->ether_dhost, broadcast_mac)
	);
}

static int is_UPnP_ssdp(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));
	const struct udphdr *udp = (struct udphdr *)
		(packet + sizeof(struct iphdr) + sizeof(struct ether_header));

	return	ipv4_equal(ip->daddr, 239,255,255,250) &&
		ip->protocol == IPPROTO_UDP &&
		ntohs(udp->dest) == 1900;
}

#define MAX_PKT_TAGS 32
static char *tags[MAX_PKT_TAGS];
static int last_tag;

static inline void print_tags(FILE *f)
{
	int i;

	for (i = 0; i < last_tag; i++) {
		fprintf(f, "%s%s", i ? "," : "", tags[i]);
	}
}

#define ADD_TAG(tag)				\
	if (last_tag < MAX_PKT_TAGS) {		\
		tags[last_tag++] = tag;		\
	}

#define SET_TAG(test,tag)				\
	if (last_tag < MAX_PKT_TAGS && test(packet)) {	\
	    tags[last_tag++] = tag;			\
	}

static void tag_packet(const void *packet)
{
	last_tag = 0;

	SET_TAG(is_bpdu, "BPDU");
	SET_TAG(is_lldp, "LLPD");
	SET_TAG(is_pxe, "PXE");
	SET_TAG(is_mcast_eth, "ETH.MCAST");
	SET_TAG(is_pvt_IPv4, "IP.PVT");
	SET_TAG(is_ll_IPv4, "IP.LL");
	SET_TAG(is_loopback_IPv4, "IP.LB");
	SET_TAG(is_doc_IPv4, "IP.DOC");
	if (is_mcast_IPv4(packet)) {
		const struct iphdr *ip = (struct iphdr *)
			(packet + sizeof(struct ether_header));
		uint32_t a = ntohl(ip->daddr);

		ADD_TAG("IP.MCAST");
		if (match_cidr(a, 239,0,0,0, 8)) ADD_TAG("MCAST.APP");
		if (match_cidr(a, 232,0,0,0, 8)) ADD_TAG("MCAST.SS");
		if (	match_cidr(a, 233,0,0,0, 24) ||
			match_cidr(a, 233,128,0,0, 24)
		)	ADD_TAG("MCAST.IANA");
		if (is_UPnP_ssdp(packet)) ADD_TAG("UPnP");
	}
}

static inline int zero16(const void *data)
{
	const uint64_t *p = data;

	return p[0] == 0 && p[1] == 0;
}

static void dump(FILE *f, const void *data, size_t size)
{
	const uint8_t *D = data;
	size_t row, col;
	int zcnt = 0;

	for (row = 0; (row * 16) < size; row++) {
		const size_t row_offset = row * 16;

		if (row && row_offset + 16 < size && zero16(D + row_offset)) {
			zcnt++;
			continue;
		}

		if (zcnt) {
			fprintf(f, "** zero bytes skipped: %d\n", zcnt * 16);
			zcnt = 0;
		}

		fprintf(f, "%08lx", row_offset);
		for (col = 0; col < 16; col++) {
			const size_t offset = row * 16 + col;

			if (offset < size)
				fprintf(f, " %02x", D[offset]);
			else
				fprintf(f, "   ");
		}
		fprintf(f, " |");
		for (col = 0; col < 16; col++) {
			const size_t offset = row * 16 + col;

			if (offset < size) {
				uint8_t c = D[offset];

				if (!isprint(c) || (isspace(c) && c != ' '))
					c = '.';
				fprintf(f, "%c", c);
			} else
				fprintf(f, " ");
		}
		fprintf(f, "|\n");
	}
}

static inline void add_serv_name(char *p, uint16_t port, const char *proto)
{
	struct servent *se = getservbyport(port, proto);

	if (se)
		// sprintf(p, "%s/%s", se->s_name, proto);
		sprintf(p, "%s", se->s_name);
	else
		// sprintf(p, "%d/%s", ntohs(port), proto);
		sprintf(p, "%d", ntohs(port));
}

static char *ip_service_name(const void *packet)
{
	struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));
	struct protoent *pe = getprotobynumber(ip->protocol);

	static char result[128];

	sprintf(result, "IP#%u", ip->protocol);

	if (!pe)
		return result;

	switch (ip->protocol) {
	case IPPROTO_TCP: /* same port layout */
	case IPPROTO_UDP: {
		struct udphdr *udp = (struct udphdr *)
			(packet + sizeof(struct iphdr) + sizeof(struct ether_header));
		char *p = result;

		add_serv_name(p, udp->source, pe->p_name);
		p += strlen(p);
		*p++ = '>';
		add_serv_name(p, udp->dest, pe->p_name);
		break;
	}
	default:
		sprintf(result, "?/%s", pe->p_name);
		break;
	}
	return result;
}

static const char *_ICMP_types[] = {
	[ICMP_ECHOREPLY] = "ECHOREPLY",	/* Echo Reply			*/
	[ICMP_DEST_UNREACH] = "DEST_UNREACH",	/* Destination Unreachable	*/
	[ICMP_SOURCE_QUENCH] = "SOURCE_QUENCH",	/* Source Quench		*/
	[ICMP_REDIRECT] = "REDIRECT",	/* Redirect (change route)	*/
	[ICMP_ECHO] = "ECHO",	/* Echo Request			*/
	[ICMP_TIME_EXCEEDED] = "TIME_EXCEEDED",	/* Time Exceeded		*/
	[ICMP_PARAMETERPROB] = "PARAMETERPROB",	/* Parameter Problem		*/
	[ICMP_TIMESTAMP] = "TIMESTAMP",	/* Timestamp Request		*/
	[ICMP_TIMESTAMPREPLY] = "TIMESTAMPREPLY",	/* Timestamp Reply		*/
	[ICMP_INFO_REQUEST] = "INFO_REQUEST",	/* Information Request		*/
	[ICMP_INFO_REPLY] = "INFO_REPLY",	/* Information Reply		*/
	[ICMP_ADDRESS] = "ADDRESS",	/* Address Mask Request		*/
	[ICMP_ADDRESSREPLY] = "ADDRESSREPLY",	/* Address Mask Reply		*/
};

static const char *_ICMP_DEST_UNREACH[] = {
	[ICMP_NET_UNREACH] = "NET_UNREACH",	/* Network Unreachable		*/
	[ICMP_HOST_UNREACH] = "HOST_UNREACH",	/* Host Unreachable		*/
	[ICMP_PROT_UNREACH] = "PROT_UNREACH",	/* Protocol Unreachable		*/
	[ICMP_PORT_UNREACH] = "PORT_UNREACH",	/* Port Unreachable		*/
	[ICMP_FRAG_NEEDED] = "FRAG_NEEDED",	/* Fragmentation Needed/DF set	*/
	[ICMP_SR_FAILED] = "SR_FAILED",		/* Source Route failed		*/
	[ICMP_NET_UNKNOWN] = "NET_UNKNOWN",	
	[ICMP_HOST_UNKNOWN] = "HOST_UNKNOWN",	
	[ICMP_HOST_ISOLATED] = "HOST_ISOLATED",	
	[ICMP_NET_ANO] = "NET_ANO",	
	[ICMP_HOST_ANO] = "HOST_ANO",	
	[ICMP_NET_UNR_TOS] = "NET_UNR_TOS",	
	[ICMP_HOST_UNR_TOS] = "HOST_UNR_TOS",	
	[ICMP_PKT_FILTERED] = "PKT_FILTERED",	/* Packet filtered */
	[ICMP_PREC_VIOLATION] = "PREC_VIOLATION",	/* Precedence violation */
	[ICMP_PREC_CUTOFF] = "PREC_CUTOFF",	/* Precedence cut off */
};

static const char *_ICMP_REDIRECT[] = {
	[ICMP_REDIR_NET] = "REDIR_NET",		/* Redirect Net			*/
	[ICMP_REDIR_HOST] = "REDIR_HOST",	/* Redirect Host		*/
	[ICMP_REDIR_NETTOS] = "REDIR_NETTOS",	/* Redirect Net for TOS		*/
	[ICMP_REDIR_HOSTTOS] = "REDIR_HOSTTOS",	/* Redirect Host for TOS	*/
};

static inline const char *ICMP_type(const struct icmp *icmp)
{
	uint8_t t = icmp->icmp_type;
	uint8_t c = icmp->icmp_code;

	if (t > NR_ICMP_TYPES) {
		static char msg[32];

		sprintf(msg, "ICMP#%02x:%02x", t, c);
		return msg;
	}
	switch (t) {
	case ICMP_DEST_UNREACH:
		if (c <= NR_ICMP_UNREACH)
			return _ICMP_DEST_UNREACH[c];
		break;
	case ICMP_REDIRECT:
		if (c <= 3)
			return _ICMP_REDIRECT[c];
		break;
	case ICMP_TIME_EXCEEDED:
		switch (c) {
		case ICMP_EXC_TTL: return "EXC_TTL";
		case ICMP_EXC_FRAGTIME: return "EXC_FRAGTIME";
		}
		break;
	}
	return _ICMP_types[t];
}

static void print_icmp(FILE *f, void *packet, ssize_t psize)
{
	struct icmp *icmp = (struct icmp *)
		(packet + sizeof(struct iphdr) + sizeof(struct ether_header));

	fprintf(f, "|%s", ICMP_type(icmp));
}

static void print_tcp(FILE *f, void *packet, ssize_t psize)
{
	fprintf(f, "|%s", ip_service_name(packet));
}

static void print_udp(FILE *f, void *packet, ssize_t psize)
{
/*
	struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));
	struct udphdr *udp = (struct udphdr *)
		(packet + sizeof(struct iphdr) + sizeof(struct ether_header));
*/
	fprintf(f, "|%s", ip_service_name(packet));
}

static void print_ipv4(FILE *f, void *packet, ssize_t psize)
{
	struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	int df = ip->tot_len & 0x4000;
	int mf = ip->tot_len & 0x2000;

	char sender[INET6_ADDRSTRLEN] = {};
	char addressee[INET6_ADDRSTRLEN] = {};

	/* Get source & target IP */
	ipv4_to_str(ip->saddr, sender, sizeof(sender));
	ipv4_to_str(ip->daddr, addressee, sizeof(addressee));

	if (last_tag < MAX_PKT_TAGS) {
		if (strcmp(addressee, "255.255.255.255") == 0)
			tags[last_tag++] = "L3*";
		if (ip->daddr == global.local_ip)
			tags[last_tag++] = "L3!";
		if (global.local_ip && ip->saddr == global.local_ip)
			tags[last_tag++] = "L3<";
		if (df)
			tags[last_tag++] = "IP.DF";
		if (mf)
			tags[last_tag++] = "IP.MF";
	}

	fprintf(f, "|%s>%s|%u|TTL=%u",
		sender, addressee,
		ntohs(ip->tot_len),
		ip->ttl
	);

	switch (ip->protocol) {
	case IPPROTO_ICMP:
		fprintf(f, "|ICMP");
		print_icmp(f, packet, psize);
		break;
	case IPPROTO_UDP:
		fprintf(f, "|UDP");
		print_udp(f, packet, psize);
		break;
	case IPPROTO_TCP:
		fprintf(f, "|TCP");
		print_tcp(f, packet, psize);
		break;
	default:{
		struct protoent *pe = getprotobynumber(ip->protocol);

		fprintf(f, "|PRTL:%u=%s", ip->protocol, pe ? pe->p_name : "?");
		break;
		}
	}
}

static int is_my_ip_packet(const void *packet)
{
	const struct iphdr *ip = (struct iphdr *)
		(packet + sizeof(struct ether_header));

	return global.local_ip && (ip->saddr == global.local_ip);
}

static void print_eth(FILE *f, void *packet, ssize_t psize)
{
	const struct ether_header *eh = packet;
	uint16_t ethertype = ntohs(eh->ether_type);

	char mac_from[32] = {};
	char mac_to[32] = {};

	/* Get source & target MAC */
	strcpy(mac_from, ether_ntoa((const struct ether_addr *) eh->ether_shost));
	strcpy(mac_to, ether_ntoa((const struct ether_addr *) eh->ether_dhost));

	if (last_tag < MAX_PKT_TAGS) {
		if (mac_equal(eh->ether_dhost, broadcast_mac))
			tags[last_tag++] = "L2*";
		if (mac_equal(eh->ether_dhost, global.local_mac))
			tags[last_tag++] = "L2!";
		if (mac_equal(eh->ether_shost, global.local_mac))
			tags[last_tag++] = "L2<";
	}

	fprintf(f, "|%s>%s", mac_from, mac_to);
	switch (ethertype) {
	case ETHERTYPE_IP:		/* IP */
		fprintf(f, "|IPv4");
		print_ipv4(f, packet, psize);
		break;
	case ETHERTYPE_IPV6:		/* IP protocol version 6 */
	case ETHERTYPE_ARP:		/* Address resolution */
	case ETHERTYPE_REVARP:		/* Reverse ARP */
	case ETHERTYPE_VLAN:		/* IEEE 802.1Q VLAN tagging */
	case ETHERTYPE_LOOPBACK:	/* used to test interfaces */
	default:
		fprintf(f, "|TYPE=%04x=%04x", eh->ether_type, ethertype);
		break;
	}
}

static void print_pxe(void *packet, ssize_t psize)
{
	const struct ether_header *eh = packet;

	if (!is_pxe(packet))
		return;

	printf("PXE%lu=%s\n", ++global.total_printed,
		ether_ntoa((const struct ether_addr *) eh->ether_shost));

	if (parm.dump_packet)
		dump(stdout, packet, psize);
}

static void print_packet(void *packet, ssize_t psize)
{
	global.total_printed++;

	tag_packet(packet);

	printf("%lu", psize);
	print_eth(stdout, packet, psize);
	printf("|");
	print_tags(stdout);
	printf("\n");

	if (is_my_ip_packet(packet)) {
		printf("but I sent it :(\n");
		return;
	}

	if (parm.dump_packet)
		dump(stdout, packet, psize);
}

static void get_local_addrs(int sockfd, const char *ifName, ipv4_addr_t *ip, eth_mac_t mac)
{
	struct ifreq if_ip = {};	/* get ip addr */

	if (ip) memset(ip, 0, sizeof(ipv4_addr_t));
	if (mac) memset(mac, 0, sizeof(eth_mac_t));

	strncpy(if_ip.ifr_name, ifName, IFNAMSIZ-1);

	/* Look up my device IP addr if possible */
	if (ioctl(sockfd, SIOCGIFADDR, &if_ip) >= 0) { /* if we can't check then don't */
		if (ip)
			*ip = ((struct sockaddr_in *)&if_ip.ifr_addr)->sin_addr.s_addr;
	}

	/* Look up my device MAC addr if possible */
	strncpy(if_ip.ifr_name, ifName, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFHWADDR, &if_ip) >= 0) { /* if we can't check then don't */
		struct sockaddr *sa = (struct sockaddr *)&if_ip.ifr_addr;
		const int af = sa->sa_family;
		const size_t data_size = sizeof(sa->sa_data);
		uint8_t *data = (uint8_t *) &sa->sa_data[0];
		if (mac) {
			if (af == ARPHRD_ETHER)
				memcpy(mac, data, data_size > 6 ? 6 : data_size);
		}
	}
}

static inline void print_stat(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);

	fprintf(stderr, "\nLocal IP '%s' on '%s' [%s]\n",
		global.local_ip_str, global.ifName, 
		ether_ntoa((const struct ether_addr *) global.local_mac));
	fprintf(stderr, "seconds spent        : %lu\n"
			"total packets seen   : %lu (%lu pps)\n"
			"total packets printed: %lu\n",
			tv.tv_sec - global.t0.tv_sec,
			global.total_count, global.total_count / (tv.tv_sec - global.t0.tv_sec),
			global.total_printed);
}

static void on_sigint(int arg)
{
	print_stat();
	/* fprintf(stderr, "Use SIGQUIT (^\\) to kill\n"); */
}

static void on_sigquit(int arg)
{
	fprintf(stderr, "\nQUIT\n");
	print_stat();
	global.do_the_job = 0;
}

static void set_flags(int sockfd, short int flags)
{
	struct ifreq ifopts = {};

	strncpy(ifopts.ifr_name, global.ifName, IFNAMSIZ-1);
	ifopts.ifr_flags = flags;

	if (ioctl(sockfd, SIOCSIFFLAGS, &ifopts)) {	/* set flags */
		perror("ioctl(SIOCSIFFLAGS)");
		close(sockfd);
		exit(EXIT_FAILURE);
	}
}

static int listener(const char *ifName)
{
	int sockfd, sockopt;
	struct ifreq ifopts = {};

	/* Open PF_PACKET socket, listening for EtherType ETHER_TYPE */
	if ((sockfd = socket(PF_PACKET, SOCK_RAW, htons(ETHER_TYPE))) == -1) {
		perror("socket");	
		exit(EXIT_FAILURE);
	}

	/* Fetch and preserve interface flags */
	strncpy(ifopts.ifr_name, ifName, IFNAMSIZ-1);
	if (ioctl(sockfd, SIOCGIFFLAGS, &ifopts)) {
		perror("ioctl(SIOCGIFFLAGS)");
		close(sockfd);
		exit(EXIT_FAILURE);
	}
	global.saved_ifru_flags = ifopts.ifr_flags;

	if (parm.promisc_mode && !(global.saved_ifru_flags & IFF_PROMISC)) {
		global.restore_flags = 1;
		set_flags(sockfd, global.saved_ifru_flags | IFF_PROMISC);
	}

	/* Allow the socket to be reused - incase connection is closed prematurely */
	if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &sockopt, sizeof(sockopt)) == -1) {
		perror("SO_REUSEADDR");
		close(sockfd);
		exit(EXIT_FAILURE);
	}

	/* Bind to device */
	if (setsockopt(sockfd, SOL_SOCKET, SO_BINDTODEVICE, ifName, IFNAMSIZ-1) == -1)	{
		perror("SO_BINDTODEVICE");
		close(sockfd);
		exit(EXIT_FAILURE);
	}
	return sockfd;
}

static void auto_exclude_ssh(void)
{
	char c, *p, *var = getenv("SSH_CLIENT") ?: getenv("SSH_CONNECTION");

	if (!var) {
		if (!parm.auto_exclude) {
			fprintf(stderr, "No SSH detected.\n");
			return;
		}
		fprintf(stderr, "Oops: cannot detect SSH\n");
		if (getenv("SUDO_COMMAND"))
			fprintf(stderr, "Use 'sudo -E' to preserve environment\n");
		exit(EXIT_FAILURE);
	}
	/*
	 * SSH_CLIENT=172.17.16.105 35606 22
	 * SSH_CONNECTION=172.17.16.105 35606 172.17.32.103 22
	 */
	for (p = var; p && *p && !isspace(*p); p++) ;
	if (!p || !*p || !isspace(*p)) {
		fprintf(stderr, "Oops: odd SSH string '%s'\n", var);
		exit(EXIT_FAILURE);
	}
	c = *p;
	*p = '\0';
	add_ignored_ip(var);
	fprintf(stderr, "SSH originator IP '%s' ignored\n", var);
	*p = c;
}

static int good_packet(const void *packet)
{
	if (parm.only) {
		return tracked_packet(packet) && !ignored_port(packet);
	}
	return !ignored_packet(packet) && !ignored_port(packet);
}

static void help(const char *argv0)
{
	fprintf(stderr,
		"Usage: %s <options...>\n"
		"Valid options:\n"
		"-I <interface>\t-- specify interface name, mandatory\n"
		"-a\t\t-- don't automagically filter out SSH originator's IP\n"
		"-x <IP>[/<bits>]\t-- filter out <IP> (IPv4 dotted quad) or subnet of <bits> prefix\n"
		"-X <MAC>\t-- filter out <MAC> (hex-colon 6 bytes)\n"
		"-y <IP>[/<bits>]\t-- watch <IP> (IPv4 dotted quad) or subnet of <bits> prefix\n"
		"-Y <MAC>\t-- watch <MAC> (hex-colon 6 bytes)\n"
		"-p\t\t-- detect PXE boot frames only\n"
		"-P\t\t-- promiscous mode\n"
		"-d\t\t-- print dump of packets\n"
		"-n\t\t-- don't ignore local traffic (null MACs)\n"
		"-c <N>\t\t-- quit after printing <N> packets\n"
		"-i\t\t-- print \"interesting\" packets\n"
		"-o\t\t-- print only selected packets\n"
		"-N <P>[,<P>...]\t-- don't print packets for service/port <P>\n"
		"\n"
		"You'd normally run it as 'sudo -E %s -I %s'\n"
		"\n",
		argv0,
		argv0, global.ifName
	);
}

extern int getopt(int argc, char * const argv[], const char *optstring);
extern char *optarg;
extern int optind, opterr, optopt;

const static char options[]="hI:x:X:apPdnc:y:Y:ioN:";

int main(int argc, char *argv[], char **envp)
{
	int sockfd;
	ssize_t numbytes;
	uint8_t buf[BUF_SIZ];

	int opt;

	/* for (opt = 0; envp[opt]; opt++) printf("env[%d]='%s'\n", opt, envp[opt]); */

	while ((opt = getopt(argc, argv, options)) != -1) {
		switch (opt) {
		case 'N':
			parm.no_srv = 1;
			fprintf(stderr, "Won't print ports/services:\n");
			ignore_ports(optarg);
			break;
		case 'o':
			parm.only = 1;
			fprintf(stderr, "Will print only selected\n");
			break;
		case 'i':
			parm.interesting = 1;
			fprintf(stderr, "Will print interesting\n");
			break;
		case 'c':
			parm.max_packets = a2i(optarg);
			fprintf(stderr, "Won't ignore null MACs\n");
			break;
		case 'n':
			global.ignored_mac_count = 0;
			fprintf(stderr, "Won't ignore null MACs\n");
			break;
		case 'P':
			parm.promisc_mode = 1;
			fprintf(stderr, "Promiscous mode\n");
			break;
		case 'p':
			parm.pxe_only = 1;
			fprintf(stderr, "PXE only\n");
			break;
		case 'd':
			parm.dump_packet = 1;
			fprintf(stderr, "Packets dumped\n");
			break;
		case 'a':
			parm.auto_exclude = 0;
			break;
		case 'I':
			parm.ifName_set = 1;
			strncpy(global.ifName, optarg, sizeof(global.ifName) - 1);
			break;
		case 'x':
			add_ignored_ip(optarg);
			break;
		case 'X':
			add_ignored_mac(optarg);
			break;
		case 'y':
			add_tracked_ip(optarg);
			break;
		case 'Y':
			add_tracked_mac(optarg);
			break;
		case 'h':
		default:
			help(argv[0]);
			exit(EXIT_FAILURE);
		}
	}
	if (!parm.ifName_set) {
		fprintf(stderr, "No interface given.\n");
		exit(EXIT_FAILURE);
	}

	if (parm.interesting) {
		static const char *interesting_mac[] = {
			/* all "01:80:c2:xx:xx:xx" are already "interesting" */
			"01:00:0c:cc:cc:cd",
			"ff:ff:ff:ff:ff:ff",
			NULL
		};
		int i;

		auto_exclude_ssh();
		for (i = 0; interesting_mac[i]; i++)
			add_tracked_mac(interesting_mac[i]);

	}

	if (parm.auto_exclude)
		auto_exclude_ssh();

	sockfd = listener(global.ifName);

	get_local_addrs(sockfd, global.ifName, &global.local_ip, global.local_mac);
	ipv4_to_str(global.local_ip, global.local_ip_str, sizeof(global.local_ip_str));
	strcpy(global.local_mac_str, ether_ntoa((const struct ether_addr *) global.local_mac));
	fprintf(stderr, "Local IP '%s' on '%s' [%s]\n",
		global.local_ip_str, global.ifName, global.local_mac_str);

	signal(SIGINT, on_sigint); /* trap ^C to see the progress, if any */
	signal(SIGQUIT, on_sigquit); /* trap ^\ to terminate */

	if (parm.max_packets) {
		fprintf(stderr, "\nI'll quit after printing %d packet%s.\n",
			parm.max_packets, parm.max_packets == 1 ? "" : "s");
	}
	fprintf(stderr, "\nUse SIGINT (^C) to see progress.\n"
		"Use SIGQUIT (^\\) to quit.\n\n");
	if (gettimeofday(&global.t0, NULL)) {
		perror("gettimeofday");
	}

	global.do_the_job = 1;
	while (global.do_the_job) {
		numbytes = recvfrom(sockfd, buf, BUF_SIZ, 0, NULL, NULL);
		global.total_count++;

		if (parm.pxe_only) {
			print_pxe(buf, numbytes);
			continue;
		}

		if (good_packet(buf))
			print_packet(buf, numbytes);

		if (parm.max_packets && global.total_printed >= parm.max_packets)
			break;
	}

	if (global.restore_flags)
		set_flags(sockfd, global.saved_ifru_flags);

	close(sockfd);
	fprintf(stderr, "done\n");
	return 0;
}
