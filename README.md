[comment]: # "SPDX-License-Identifier:  Apache-2.0"

# Hop-by-hop IPv4 Privacy in P4

## Introduction

This project extends the standard **P4 basic forwarding** exercise with a **hop-by-hop IPv4 privacy scheme**. The goal is to show, in a concrete P4/BMv2 setting, how we can:

1. Randomize the **host portion of the source IPv4 address** and **TCP source port** at the edge of the network.
2. Keep the **core switches stateless** with respect to flows.
3. Preserve **correctness and compatibility** with existing client–server applications.

The implementation follows the protocol described in the report *"P4 and Privacy"* and is deployed on a Mininet topology using BMv2 `simple_switch` and P4Runtime.

## Topology

We use the same fat-tree pod topology as in the original `basic.p4` tutorial:

![pod-topo](./pod-topo/pod-topo.png)

In this project we interpret the nodes as follows:

* **Hosts**

  * `h1`: client (inside the privacy-enabled domain)
  * `h4`: server (outside or at the edge of the domain)
* **Switches**

  * `s1`, `s2`: **privacy-capable edge routers (PGB routers)**
  * `s3`, `s4`: **core routers**, which only perform IPv4 longest-prefix matching and remain stateless w.r.t. flows

Traffic flows from `h1` → `s1` → `s3` → `s4` → `h4` (and back). The privacy logic is applied at the edges, while the core simply forwards encrypted packets.

## Data Plane Design (High-Level)

The main P4 program (e.g., `basic.p4` or `privacy_hophop.p4`, depending on how you named it) is written for the **v1model** architecture and contains:

* **Headers**

  * `ethernet_t`: standard Ethernet header
  * `ipv4_t`: standard IPv4 header
  * `tcp_t`: TCP header for transport-layer ports
  * `privacy_t`: custom header carrying a 32-bit `nonce`
* **Parser**

  * Parses Ethernet → IPv4 → TCP
  * If `ipv4.protocol == PROTO_PRIV` (custom value, e.g., 250), it also parses the `privacy_t` header.
* **Ingress control (`MyIngress`)**

  * `ipv4_lpm` table: standard IPv4 LPM forwarding (sets egress port and next-hop MAC; used by all switches).
  * `privacy_policy` table: per-port policy that decides whether to **encrypt** or **decrypt** based on the ingress port and direction.
  * Actions:

    * `encrypt_c2s()`: applied on **client-to-server** flows at the edge.

      * Derives a per-packet **nonce** from `{ dst IP, dst port, ingress_global_timestamp }` using `HashAlgorithm.crc32`.
      * Sets `hdr.privacy` valid and stores the nonce.
      * Changes `ipv4.protocol` from TCP (6) to a custom value (e.g., 250).
      * Uses a keyed hash (with `PRIV_KEY`) to derive a pad and XORs it with:

        * `ipv4.srcAddr`
        * `tcp.srcPort`
    * `decrypt_c2s()`: applied on the **reverse direction** at the opposite edge.

      * Reads the stored `nonce` from `hdr.privacy`.
      * Recomputes the same pad and XORs it back into `ipv4.srcAddr` and `tcp.srcPort` to recover the original values.
      * Clears `hdr.privacy` and restores `ipv4.protocol = PROTO_TCP`.
* **Egress and Deparser**

  * `MyEgress`: empty in this project (no extra logic in egress).
  * `MyDeparser`: emits headers in the order: Ethernet → IPv4 → Privacy (if valid) → TCP.

Core switches (`s3`, `s4`) use **only** `ipv4_lpm` and never inspect or modify the `privacy_t` header. All cryptographic-style work is confined to the edge.

## Repository Layout

Typical layout for this exercise:

* `Makefile` – builds the P4 program and starts Mininet with BMv2 and P4Runtime.
* `basic.p4` or `privacy_hophop.p4` – main P4 data-plane program implementing forwarding + privacy logic.
* `pod-topo/topology.json` – Mininet topology description and host configuration.
* `s1-runtime.json`, `s2-runtime.json`, `s3-runtime.json`, `s4-runtime.json` – P4Runtime control-plane configs for each switch.
* `logs/` – BMv2 log files (created at runtime).
* `pcaps/` – optional directory for packet captures (you can create this).

> ⚠️ If you changed the P4 source name, make sure `P4SRC` in the `Makefile` points to the correct file.

## 1. Running the Topology

From the project directory inside the VM (e.g., `~/tutorials/exercises/privacy_hophop`):

```bash
make run
```

This will:

1. Compile the P4 source specified in the `Makefile`.
2. Start the Mininet topology with `h1`, `h4`, and `s1`–`s4`.
3. Load P4 programs on all switches and install the table entries from `sX-runtime.json`.
4. Configure host IPs, routes, and ARP entries using `topology.json`.

If everything succeeds, you should see a Mininet prompt:

```text
mininet>
```

To stop everything:

```bash
make stop   # stop Mininet and switches
make clean  # optional: remove logs, pcaps, and build artifacts
```

## 2. Switching Between Basic and Encrypted Modes

You can run the topology in **two modes**:

1. **Basic IPv4 forwarding (no privacy)** – behaves like the original tutorial.
2. **Privacy-enabled mode** – applies hop-by-hop encryption/decryption at the edges.

There are two common ways to switch between these modes, depending on how your repo is set up.

### Option A – Using Two Different P4 Programs

If you have **two separate P4 files**, for example:

* `basic.p4` – plain IPv4 forwarding (no privacy logic)
* `privacy_hophop.p4` – forwarding + hop-by-hop privacy

Then you can switch modes by editing `P4SRC` in the `Makefile`:

```makefile
# For basic mode
P4SRC = basic.p4

# For privacy mode
# P4SRC = privacy_hophop.p4
```

Then run:

```bash
make clean
make run
```

### Option B – Toggling Privacy Inside a Single P4 Program

If you have **one P4 file** containing both forwarding and privacy logic, you can toggle privacy by enabling or disabling the call to `privacy_policy.apply()` inside `MyIngress.apply`.

Example structure:

```p4
apply {
    if (hdr.ipv4.isValid()) {
        if (hdr.tcp.isValid()) {
            privacy_policy.apply();
        }
        ipv4_lpm.apply();
    }
}
```

* **Privacy mode**: keep `privacy_policy.apply();` **enabled**.
* **Basic mode** (no encryption): **comment it out**:

  ```p4
  apply {
      if (hdr.ipv4.isValid()) {
          if (hdr.tcp.isValid()) {
              // privacy_policy.apply();   // disabled for baseline
          }
          ipv4_lpm.apply();
      }
  }
  ```

Then recompile and run:

```bash
make clean
make run
```

This way, you can easily compare:

* Baseline IPv4 behavior (no header randomization).
* Privacy-enabled behavior (encryption at the edges).

## 3. Basic Sanity Tests

Once Mininet is running, use the `mininet>` prompt.

### 3.1 Connectivity

```bash
mininet> h1 ping -c 3 h4
```

You should see successful replies in both basic and privacy modes. In privacy mode, the packet headers are rewritten inside the network, but end-to-end connectivity is preserved.

### 3.2 TCP Flow with iperf3

```bash
mininet> h4 iperf3 -s &
mininet> h1 iperf3 -c 10.0.4.4 -t 20
```

This produces a long-lived TCP flow from `h1` to `h4`. The sender summary printed by `iperf3` is used to compute throughput.

## 4. Measuring Privacy Metrics

The privacy evaluation looks at:

* **Pseudonym churn** `C_IDS` (how fast `(IP_src, Port_src)` identifiers change).
* **IP-based linkability** `L_IP` (overlap between edge and core source IPs).
* **Entropy** `H(S_core)` (uncertainty in the attacker’s view at the core).

All metrics are computed from packet traces captured at `s1`:

* **Edge view**: interface towards `h1` (e.g., `s1-eth1`).
* **Core view**: interface towards `s3` (e.g., `s1-eth4`).

### 4.1 Capture Traces

At the `mininet>` prompt:

```bash
mininet> xterm s1 h1 h4
```

In the `s1` xterm:

```bash
mkdir -p pcaps

# Edge-side traffic (towards h1)
tcpdump -i s1-eth1 -n -w pcaps/s1-eth1_in.pcap &

# Core-side traffic (towards s3)
tcpdump -i s1-eth4 -n -w pcaps/s1-eth4_out.pcap &
```

Then run `iperf3` from `h1` to `h4` as above. After it completes, stop `tcpdump` with `Ctrl+C` in the `s1` xterm.

You now have two pcaps:

* `pcaps/s1-eth1_in.pcap` – edge view
* `pcaps/s1-eth4_out.pcap` – core view

### 4.2 Pseudonym Churn `C_IDS`

On the VM shell in the repo directory:

```bash
cd ~/tutorials/exercises/privacy_hophop

# Extract distinct (IP.src, port.src) on the core side
tcpdump -nnr pcaps/s1-eth4_out.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/.$//' \
  | sort | uniq > core_ids.txt

N_IDS=$(wc -l < core_ids.txt)
echo "N_IDS = $N_IDS"
```

If the experiment duration is `T` seconds (e.g., `T = 20`):

```bash
python3 - << EOF
N = $N_IDS
T = 20.0
print(f"C_IDS = {N/T:.1f} IDs/s")
EOF
```

### 4.3 IP-based Linkability `L_IP`

```bash
# Edge-side source IPs
tcpdump -nnr pcaps/s1-eth1_in.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/\.[0-9]*$//' \
  | sort -u > edge_ips.txt

# Core-side source IPs
tcpdump -nnr pcaps/s1-eth4_out.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/\.[0-9]*$//' \
  | sort -u > core_ips.txt

# Intersection size
INTERSECT=$(comm -12 edge_ips.txt core_ips.txt | wc -l)
EDGE_SIZE=$(wc -l < edge_ips.txt)

echo "|S_edge ∩ S_core| = $INTERSECT"
echo "|S_edge| = $EDGE_SIZE"

python3 - << EOF
I = $INTERSECT
E = $EDGE_SIZE
if E == 0:
    print("L_IP undefined (no edge sources)")
else:
    print(f"L_IP = {I / E:.3f}")
EOF
```

In privacy mode, you should observe `L_IP ≈ 0`, since the client’s true IP does not appear in the core trace.

### 4.4 Entropy `H(S_core)`

```bash
# Count how often each core identifier appears
tcpdump -nnr pcaps/s1-eth4_out.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/.$//' \
  | sort | uniq -c > core_ids_counts.txt
```

Then compute Shannon entropy:

```bash
python3 - << 'EOF'
import math
import sys

counts = []
with open('core_ids_counts.txt') as f:
    for line in f:
        parts = line.strip().split()
        if not parts:
            continue
        c = int(parts[0])
        counts.append(c)

N = sum(counts)
if N == 0:
    print("No packets found in core_ids_counts.txt")
    sys.exit(0)

H = 0.0
for c in counts:
    p = c / N
    H -= p * math.log2(p)

print(f"H(S_core) = {H:.2f} bits")
EOF
```

A single stable identifier gives `H ≈ 0`. A nearly uniform spread over many pseudonyms gives `H` close to `log2(N_IDS)`.

## 5. Measuring Performance (Throughput & RTT)

We measure the performance impact of privacy using **ping** and **iperf3**.

### 5.1 Baseline IPv4 (No Privacy)

Run in **basic mode** using either:

* `P4SRC = basic.p4` in the `Makefile`, or
* Commenting out `privacy_policy.apply()` as shown above.

Then:

```bash
make clean
make run
```

From `mininet>`:

```bash
# RTT baseline
mininet> h1 ping -c 50 h4

# Throughput baseline
mininet> h4 iperf3 -s &
mininet> h1 iperf3 -c 10.0.4.4 -t 10
```

Record:

* `R_b` – mean RTT from `ping` summary.
* `T_b` – average throughput from `iperf3` sender.

### 5.2 Privacy-Enabled Mode

Switch back to privacy mode (set `P4SRC` to the privacy program, or re-enable `privacy_policy.apply()`), then:

```bash
make clean
make run
```

From `mininet>`:

```bash
# RTT with privacy
mininet> h1 ping -c 50 h4

# Throughput with privacy
mininet> h4 iperf3 -s &
mininet> h1 iperf3 -c 10.0.4.4 -t 10
```

Record:

* `R_p` – mean RTT with privacy.
* `T_p` – average throughput with privacy.

### 5.3 Computing Overheads

Using the recorded values:

* RTT increase:

  ```text
  ΔR = R_p − R_b
  Rel_R = ΔR / R_b
  ```

* Throughput overhead:

  ```text
  Overhead_T = 1 − T_p / T_b
  ```

Example from the report:

* `R_b = 9.9 ms`, `R_p = 10.9 ms` → `ΔR = 1.0 ms`, `Rel_R ≈ 10%`
* `T_b = 14.3 Mbit/s`, `T_p = 11.9 Mbit/s` → `Overhead_T ≈ 16.8%`

* How the system behaves in **basic vs encrypted** modes.
* How to reproduce the **privacy** and **performance** results directly from your code and environment.
