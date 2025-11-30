
[comment]: # (SPDX-License-Identifier:  Apache-2.0)

# Implementing Basic Forwarding

## Introduction

The objective of this exercise is to write a P4 program that
implements basic forwarding. To keep things simple, we will just
implement forwarding for IPv4.

With IPv4 forwarding, the switch must perform the following actions
for every packet: (i) update the source and destination MAC addresses,
(ii) decrement the time-to-live (TTL) in the IP header, and (iii)
forward the packet out the appropriate port.

Your switch will have a single table, which the control plane will
populate with static rules. Each rule will map an IP address to the
MAC address and output port for the next hop. We have already defined
the control plane rules, so you only need to implement the data plane
logic of your P4 program.

We will use the following topology for this exercise. It is a single
pod of a fat-tree topology and henceforth referred to as pod-topo:
![pod-topo](./pod-topo/pod-topo.png)

Our P4 program will be written for the V1Model architecture implemented
on P4.org's bmv2 software switch. The architecture file for the V1Model
can be found at: /usr/local/share/p4c/p4include/v1model.p4. This file
desribes the interfaces of the P4 programmable elements in the architecture,
the supported externs, as well as the architecture's standard metadata
fields. We encourage you to take a look at it.

> **Spoiler alert:** There is a reference solution in the `solution`
> sub-directory. Feel free to compare your implementation to the
> reference.

## Prerequisite
To ensure a smooth experience with the tutorials, it's essential to review and follow the [Obtaining required software guidelines](https://github.com/p4lang/tutorials#obtaining-required-software) to install required development tools.

## Step 1: Run the (incomplete) starter code

The directory with this README also contains a skeleton P4 program,
`basic.p4`, which initially drops all packets. Your job will be to
extend this skeleton program to properly forward IPv4 packets.

Before that, let's compile the incomplete `basic.p4` and bring
up a switch in Mininet to test its behavior.

1. In your shell, run:
   ```bash
   make run
   ```
   This will:
   * compile `basic.p4`, and
   * start the pod-topo in Mininet and configure all switches with
   the appropriate P4 program + table entries, and
   * configure all hosts with the commands listed in
   [pod-topo/topology.json](./pod-topo/topology.json)

2. You should now see a Mininet command prompt. Try to ping between
   hosts in the topology:
   ```bash
   mininet> h1 ping h2
   mininet> pingall
   ```
3. Type `exit` to leave each xterm and the Mininet command line.
   Then, to stop mininet:
   ```bash
   make stop
   ```
   And to delete all pcaps, build files, and logs:
   ```bash
   make clean
   ```

The ping failed because each switch is programmed
according to `basic.p4`, which drops all packets on arrival.
Your job is to extend this file so it forwards packets.

[comment]: # "SPDX-License-Identifier:  Apache-2.0"

# Hop-by-hop IPv4 Privacy in P4

## Overview

This project implements the hop-by-hop IPv4 privacy scheme described in the **"P4 and Privacy"** report. The data plane is written in P4_16 for the v1model architecture and runs on the BMv2 `simple_switch` target inside Mininet.

At a high level:

* The **edge switches** (`s1`, `s2`) act as privacy-capable PGB routers.
* The **core switches** (`s3`, `s4`) forward packets using plain IPv4 longest-prefix matching and remain **stateless** with respect to flows.
* For selected TCP flows between the client (`h1`) and server (`h4`), the edge switch:

  * Derives a per-packet nonce from the destination address, destination port, and ingress timestamp.
  * Uses a simple keyed construction to generate a pad.
  * XORs the pad with the IPv4 source address and TCP source port.
  * Stores the nonce in a custom `privacy_t` header and changes the IPv4 protocol field.
* On the return path, the opposite edge switch reverses the transformation using the stored nonce and restores the original IPv4/TCP header fields.

This README explains how to:

1. Build and run the Mininet topology.
2. Verify that the P4 pipeline works as expected.
3. Reproduce the **privacy** and **performance** metrics from the report.
4. Edit this README and the P4 code inside the VM.

## Repository Layout

Key files and directories (names may vary slightly depending on how you cloned/copied the exercise):

* `Makefile`
  Orchestrates compilation of the P4 program, starts Mininet, and configures switches.
* `*.p4`
  The main P4 program referenced by `P4SRC` in the `Makefile` (e.g., `basic.p4`, `privacy_hophop.p4`, etc.). This file contains:

  * Header definitions (`ethernet_t`, `ipv4_t`, `tcp_t`, `privacy_t`).
  * Parser and deparser.
  * `MyIngress` control with `ipv4_lpm` and `privacy_policy` tables.
* `pcaps/`
  Optional directory where you can store packet captures (ignored by Git if `.gitignore` is configured as suggested).
* `logs/`
  BMv2 log files produced while the topology runs. Helpful for debugging.
* `sX-runtime.json`
  P4Runtime control-plane configuration files used by the `Makefile` to populate switch tables.

If you rename the P4 file, make sure to update the `P4SRC` variable in the `Makefile` so that `make run` compiles the correct source.

## Prerequisites

The project assumes you are using the standard P4 tutorials VM or an equivalent environment with:

* `p4c` (P4_16 compiler)
* BMv2 `simple_switch` target
* Mininet
* Python 3
* `iperf3`
* `tcpdump`

If you are using the official P4 tutorials VM, all of these are already installed.

## 1. Running the Topology

From inside the project directory (e.g., `~/tutorials/exercises/privacy_hophop`):

```bash
make run
```

This will:

1. Compile the P4 program specified in the `Makefile`.
2. Start the Mininet topology with four P4 switches (`s1`–`s4`) and two hosts (`h1` and `h4`).
3. Configure each switch with its P4 program and table entries using P4Runtime.
4. Configure host IPs, routes, and ARP entries from `topology.json`.

After a successful start you should see a Mininet prompt:

```text
mininet>
```

To clean up when you are done:

```bash
# Stop Mininet and kill switches
make stop

# Optionally remove build artifacts, pcaps, and logs
make clean
```

## 2. Basic Sanity Tests

From the `mininet>` prompt:

### 2.1 Check connectivity

```bash
mininet> h1 ping -c 3 h4
```

If privacy is enabled correctly, the ping should succeed and the data plane should:

* Rewrite and encrypt the `(src IP, src port)` on the **client-to-server** direction at the edge.
* Decrypt and restore the original values at the opposite edge.

### 2.2 TCP flow with iperf3

Still at the `mininet>` prompt:

```bash
mininet> h4 iperf3 -s &
mininet> h1 iperf3 -c 10.0.4.4 -t 20
```

* `h4` runs an `iperf3` server.
* `h1` sends a 20-second TCP flow to `h4`.
* The reported average throughput will be used for performance metrics.

When finished, stop the `iperf3` server on `h4` with `Ctrl+C` in its xterm (if opened) or kill the process from Mininet.

## 3. Measuring Privacy Metrics

The report evaluates three main privacy metrics:

* **Pseudonym churn** `C_IDS`
* **IP-based linkability** `L_IP`
* **Entropy of identifiers** `H(S_core)`

All of these are computed from packet traces captured at two vantage points on `s1`:

1. **Edge view** – interface towards `h1` (real client address visible).
2. **Core view** – interface towards the core (`s3`) where identifiers are encrypted.

### 3.1 Capture traces

From the `mininet>` prompt, open xterms for `s1` and `h1` / `h4` if needed:

```bash
mininet> xterm s1 h1 h4
```

In the `s1` xterm:

```bash
mkdir -p pcaps

# Client-edge view (towards h1)
tcpdump -i s1-eth1 -n -w pcaps/s1-eth1_in.pcap &

# Core-facing view (towards s3)
tcpdump -i s1-eth4 -n -w pcaps/s1-eth4_out.pcap &
```

Then, in the `h4` and `h1` xterms, start the `iperf3` experiment:

```bash
# On h4
iperf3 -s

# On h1
iperf3 -c 10.0.4.4 -t 20
```

After `iperf3` finishes, stop the `tcpdump` processes on `s1` with `Ctrl+C` in the `s1` xterm.

You now have two pcaps:

* `pcaps/s1-eth1_in.pcap` – edge view
* `pcaps/s1-eth4_out.pcap` – core (encrypted) view

### 3.2 Pseudonym churn `C_IDS`

Pseudonyms are defined as `(IP_src, Port_src)` pairs observed at the core.

On the VM shell (inside the project directory):

```bash
cd ~/tutorials/exercises/privacy_hophop

# Count distinct (IP.src,port.src) strings in the core view
tcpdump -nnr pcaps/s1-eth4_out.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/.$//' \
  | sort | uniq > core_ids.txt

N_IDS=$(wc -l < core_ids.txt)
echo "N_IDS = $N_IDS"
```

If the flow lasted `T` seconds (e.g., `T = 20`), the churn rate is:

```bash
C_IDS = N_IDS / T
```

You can compute it directly:

```bash
python3 - << EOF
N = $N_IDS
T = 20.0
print(f"C_IDS = {N/T:.1f} IDs/s")
EOF
```

### 3.3 IP-based linkability `L_IP`

We compare the **set of source IPs** at the edge and at the core.

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

In the privacy-enabled configuration you should observe `L_IP ≈ 0`, because the client’s real IP (e.g., `10.0.1.1`) never appears at the core.

### 3.4 Entropy of identifiers `H(S_core)`

First, compute the frequency of each pseudonym in the core view:

```bash
# core_ids.txt already contains all distinct identifiers; now get counts
tcpdump -nnr pcaps/s1-eth4_out.pcap 'tcp' \
  | awk '/IP/ {print $3}' \
  | sed 's/.$//' \
  | sort | uniq -c > core_ids_counts.txt
```

Then feed the counts into a small Python snippet to compute Shannon entropy:

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

For a single stable identifier you should see `H ≈ 0`. With privacy enabled you should see entropy close to `log2(N_IDS)`.

## 4. Measuring Performance (Throughput & RTT)

We measure performance using:

* Average RTT from 50 ICMP echo requests (`ping`).
* Average TCP throughput from a 10-second `iperf3` run.

### 4.1 Baseline IPv4 (no privacy)

To obtain baseline values, temporarily **disable the privacy logic**. One simple way is to comment out the call to `privacy_policy.apply()` in the `MyIngress.apply` block:

```p4
apply {
    if (hdr.ipv4.isValid()) {
        if (hdr.tcp.isValid()) {
            // Temporarily disable privacy for baseline
            // privacy_policy.apply();
        }
        ipv4_lpm.apply();
    }
}
```

Recompile and start Mininet:

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

* `R_b` – average RTT (from the last line of `ping`).
* `T_b` – average throughput (from `iperf3` sender summary).

### 4.2 Privacy-enabled configuration

Re-enable the call to `privacy_policy.apply()` in `MyIngress.apply`, recompile, and run again:

```bash
make clean
make run
```

Then from `mininet>`:

```bash
# RTT with privacy
mininet> h1 ping -c 50 h4

# Throughput with privacy
mininet> h4 iperf3 -s &
mininet> h1 iperf3 -c 10.0.4.4 -t 10
```

Record:

* `R_p` – RTT with privacy.
* `T_p` – throughput with privacy.

### 4.3 Computing the overhead

Using the values above:

* Absolute RTT increase:

  ```text
  ΔR = R_p − R_b
  ```

* Relative RTT increase:

  ```text
  Rel_R = ΔR / R_b
  ```

* Throughput overhead:

  ```text
  Overhead_T = 1 − T_p / T_b
  ```

Example (numbers from the report):

* `R_b = 9.9 ms`, `R_p = 10.9 ms` → `ΔR = 1.0 ms`, `Rel_R ≈ 10%`
* `T_b = 14.3 Mbit/s`, `T_p = 11.9 Mbit/s` → `Overhead_T ≈ 16.8%`

