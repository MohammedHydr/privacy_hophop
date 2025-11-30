/* SPDX-License-Identifier: Apache-2.0 */



#include <core.p4>

#include <v1model.p4>



// ---------------------------------------------------------------------------

// Constants & typedefs

// ---------------------------------------------------------------------------



const bit<16> TYPE_IPV4 = 0x0800;

const bit<8> PROTO_TCP = 6;

const bit<8> PROTO_PRIV = 250;



typedef bit<48> macAddr_t;

typedef bit<32> ip4Addr_t;

typedef bit<9> egressSpec_t;



const ip4Addr_t CLIENT_IP = 0x0a000101;

const ip4Addr_t SERVER_IP = 0x0a000404;

const bit<32> PRIV_KEY = 32w0xa5a5a5a5;



// ---------------------------------------------------------------------------

// Headers

// ---------------------------------------------------------------------------



header ethernet_t {

macAddr_t dstAddr;

macAddr_t srcAddr;

bit<16> etherType;

}



header ipv4_t {

bit<4> version;

bit<4> ihl;

bit<8> diffserv;

bit<16> totalLen;

bit<16> identification;

bit<3> flags;

bit<13> fragOffset;

bit<8> ttl;

bit<8> protocol;

bit<16> hdrChecksum;

ip4Addr_t srcAddr;

ip4Addr_t dstAddr;

}



header tcp_t {

bit<16> srcPort;

bit<16> dstPort;

bit<32> seqNo;

bit<32> ackNo;

bit<4> dataOffset;

bit<3> reserved;

bit<9> flags;

bit<16> window;

bit<16> checksum;

bit<16> urgentPtr;

}



header privacy_t {

bit<32> nonce;

}



struct metadata_t { }



struct headers {

ethernet_t ethernet;

ipv4_t ipv4;

privacy_t privacy;

tcp_t tcp;

}



// ---------------------------------------------------------------------------

// Parser

// ---------------------------------------------------------------------------



parser MyParser(packet_in packet,

out headers hdr,

inout metadata_t meta,

inout standard_metadata_t standard_metadata) {



state start {

transition parse_ethernet;

}



state parse_ethernet {

packet.extract(hdr.ethernet);

transition select(hdr.ethernet.etherType) {

TYPE_IPV4: parse_ipv4;

default: accept;

}

}



state parse_ipv4 {

packet.extract(hdr.ipv4);

transition select(hdr.ipv4.protocol) {

PROTO_TCP: parse_tcp;

PROTO_PRIV: parse_privacy;

default: accept;

}

}



state parse_privacy {

packet.extract(hdr.privacy);

transition parse_tcp;

}



state parse_tcp {

packet.extract(hdr.tcp);

transition accept;

}

}



// ---------------------------------------------------------------------------

// Checksums (Handled by Host Offloading)

// ---------------------------------------------------------------------------



control MyVerifyChecksum(inout headers hdr, inout metadata_t meta) { apply { } }

control MyComputeChecksum(inout headers hdr, inout metadata_t meta) { apply { } }



// ---------------------------------------------------------------------------

// Ingress

// ---------------------------------------------------------------------------



control MyIngress(inout headers hdr,

inout metadata_t meta,

inout standard_metadata_t standard_metadata) {



action drop() {

mark_to_drop(standard_metadata);

}



action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {

standard_metadata.egress_spec = port;

hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;

hdr.ethernet.dstAddr = dstAddr;

}



action encrypt_c2s() {

if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {

// Check if flow is h1 <-> h4

if ((hdr.ipv4.srcAddr == CLIENT_IP && hdr.ipv4.dstAddr == SERVER_IP) ||

(hdr.ipv4.srcAddr == SERVER_IP && hdr.ipv4.dstAddr == CLIENT_IP)) {


bit<32> nonce;

hash(nonce, HashAlgorithm.crc32, (bit<32>)0,

{ hdr.ipv4.dstAddr, hdr.tcp.dstPort, (bit<32>)standard_metadata.ingress_global_timestamp },

(bit<32>)0xffffffff);



hdr.privacy.setValid();

hdr.privacy.nonce = nonce;

hdr.ipv4.protocol = PROTO_PRIV;



bit<32> pad;

hash(pad, HashAlgorithm.crc32, (bit<32>)0, { PRIV_KEY, nonce }, (bit<32>)0xffffffff);



// --- ENCRYPTION LOGIC ---

// 1. Encrypt IP

hdr.ipv4.srcAddr = hdr.ipv4.srcAddr ^ pad;

// 2. Encrypt Port (Use lower 16 bits of the same pad)

hdr.tcp.srcPort = hdr.tcp.srcPort ^ (bit<16>)pad;

}

}

}



action decrypt_c2s() {

if (hdr.ipv4.isValid() && hdr.tcp.isValid() && hdr.privacy.isValid()) {

if (hdr.ipv4.protocol == PROTO_PRIV) {

if (hdr.ipv4.dstAddr == CLIENT_IP || hdr.ipv4.dstAddr == SERVER_IP) {


bit<32> nonce = hdr.privacy.nonce;

bit<32> pad;

hash(pad, HashAlgorithm.crc32, (bit<32>)0, { PRIV_KEY, nonce }, (bit<32>)0xffffffff);



// --- DECRYPTION LOGIC ---

// 1. Decrypt IP

hdr.ipv4.srcAddr = hdr.ipv4.srcAddr ^ pad;

// 2. Decrypt Port

hdr.tcp.srcPort = hdr.tcp.srcPort ^ (bit<16>)pad;



hdr.privacy.setInvalid();

hdr.ipv4.protocol = PROTO_TCP;

}

}

}

}



table ipv4_lpm {

key = { hdr.ipv4.dstAddr : lpm; }

actions = { ipv4_forward; drop; }

size = 1024;

default_action = drop();

}



table privacy_policy {

key = { standard_metadata.ingress_port : exact; }

actions = { encrypt_c2s; decrypt_c2s; NoAction; }

size = 8;

default_action = NoAction();

}



apply {

if (hdr.ipv4.isValid()) {

if (hdr.tcp.isValid()) {

privacy_policy.apply();

}

ipv4_lpm.apply();

}

}

}



// ---------------------------------------------------------------------------

// Egress & Deparser

// ---------------------------------------------------------------------------



control MyEgress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) { apply { } }



control MyDeparser(packet_out packet, in headers hdr) {

apply {

packet.emit(hdr.ethernet);

packet.emit(hdr.ipv4);

packet.emit(hdr.privacy);

packet.emit(hdr.tcp);

}

}



V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(), MyEgress(), MyComputeChecksum(), MyDeparser()) main;
