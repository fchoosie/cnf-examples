# SONiC-VPP L3 BGP EVPN

This example demonstrates the integration of a high-performance software data plane ([VPP](https://fd.io/)) with a standardized network operating system ([SONiC](https://sonicfoundation.dev/)) to run advanced data center fabric protocols ([BGP EVPN](https://pantheon.tech/blog-news/what-is-bgp-evpn/)).

You will see a 2-site EVPN-VXLAN lab using **SONiC** + **VPP** data plane. The lab shows how: 
- **BGP EVPN** routes are signaled between two router nodes
- How VPP-created VXLAN tunnels forward L2 traffic so remote PCs appear on the same L2 VNI

This folder ships **two** topologies:

| | **Topology 1** (`sonic-vpp01`) | **Topology 2** (`sonic-vpp02`) |
|---|---|---|
| Launch / stop | `./run.sh` / `./stop.sh` | `./run2.sh` / `./stop2.sh` |
| Image tag | `vxlan-poc-260225` | `vxlan-poc-260421` |
| Routers | 2 (SONiC + VPP) | 2 (SONiC + VPP) |
| PCs | 2 (PC1, PC2) | 4 (PC1–PC4) |
| Underlay | `10.0.1.0/31`, iBGP AS 65100 | `10.0.1.0/31`, iBGP AS 65100 |
| VTEPs | R1 `10.0.1.1`, R2 `10.0.1.0` | R1 `10.0.1.1`, R2 `10.0.1.0` |
| VLAN → VNI | VLAN 100 → VNI 1000 | VLAN 100 → VNI 1000, VLAN 200 → VNI 2000 |
| Access ports | Ethernet4 | Ethernet4, Ethernet8 |
| Tenant subnets | `168.95.0.0/16` (single) | `10.100.1.0/24`, `10.200.1.0/24` |
| Demonstrates | Single stretched L2 VNI | Multi-VNI / multi-tenant isolation |

Both use **iBGP** (same AS 65100 on both ends) with the L2VPN/EVPN address family and
`advertise-all-vni`, so EVPN Type-2 (MAC/IP) and Type-3 (IMET) routes auto-provision the
VPP VXLAN tunnels between VTEPs.

> **Interface mapping:** in ContainerLab's `sonic-vm` kind, a container's `ethN` maps to
> SONiC port `Ethernet(4*(N-1))` — so `eth1`→`Ethernet0`, `eth2`→`Ethernet4`, `eth3`→`Ethernet8`.

### Topology 1 — `sonic-vpp01.clab.yml` (`run.sh`)

Single L2 VNI stretched across two sites. Both PCs live in the **same** IP subnet
(`168.95.0.0/16`) yet sit on different routers — proving the L2 stretch over VXLAN.

```
                          iBGP  AS 65100  (L2VPN/EVPN + IPv4 unicast)
                       advertise-all-vni  /  no ebgp-requires-policy
        ┌─────────────────────────────────────────────────────────────────────┐
        │                       UNDERLAY  10.0.1.0/31                         │
        │                                                                     │
┌───────┴────────────────────┐                         ┌──────────────────────┴──────┐
│         router1            │  eth1          eth1     │           router2           │
│      (SONiC + VPP)         │◄───────────────────────►│        (SONiC + VPP)        │
│   sonic-vpp-vs:...260225   │  Ethernet0  Ethernet0   │    sonic-vpp-vs:...260225   │
│                            │ 10.0.1.1/31 10.0.1.0/31 │                             │ 
│  router-id  10.0.1.1       │                         │      router-id  10.0.1.0    │
│  VTEP       10.0.1.1       │                         │      VTEP       10.0.1.0    │
│                            │                         │                             │
│  VLAN 100 ── VNI 1000      │                         │      VLAN 100 ── VNI 1000   │
│  member: Ethernet4         │                         │      member: Ethernet4      │
└───────┬────────────────────┘                         └──────────────────┬──────────┘
        │ eth2 / Ethernet4                              eth2 / Ethernet4  │
        │                                                                 │
        │ eth2                                                      eth2  │
┌───────┴────────┐                                              ┌─────────┴────────┐
│      PC1       │                                              │       PC2        │
│ 168.95.10.2/16 │                                              │  168.95.10.1/16  │
│ aa:aa:aa:aa:   │                                              │  be:ef:be:ef:    │
│      aa:aa     │                                              │       be:ef      │
└────────────────┘                                              └──────────────────┘
         └───────────────── same L2 domain / VNI 1000 ────────────────────┘
                    VXLAN tunnel  10.0.1.1 ◄─── VNI 1000 ───► 10.0.1.0
                        (VPP-created; EVPN Type-2/3 signalled)
```

### Topology 2 — `sonic-vpp02.clab.yml` (`run2.sh`)

Same underlay, but **two** parallel L2 VNIs (multi-tenant). Each VNI is an isolated
broadcast domain stretched across both sites; the two subnets do not talk to each other.

```
                          iBGP  AS 65100  (L2VPN/EVPN + IPv4 unicast)
                              advertise-all-vni  (all VNIs)
        ┌─────────────────────────────────────────────────────────────────────┐
        │                       UNDERLAY  10.0.1.0/31                         │
┌───────┴─────────────────────┐                         ┌─────────────────────┴──────┐
│         router1             │  eth1             eth1  │        router2             │
│      (SONiC + VPP)          │◄──────────────────────► │      (SONiC + VPP)         │
│   sonic-vpp-vs:...260421    │  Ethernet0  Ethernet0   │  sonic-vpp-vs:...260421    │
│                             │ 10.0.1.1/31 10.0.1.0/31 │                            │
│  router-id / VTEP 10.0.1.1  │                         │ router-id / VTEP 10.0.1.0  │
│                             │                         │                            │
│  VLAN 100 ─ VNI 1000 ─ Eth4 │                         │ VLAN 100 ─ VNI 1000 ─ Eth4 │
│  VLAN 200 ─ VNI 2000 ─ Eth8 │                         │ VLAN 200 ─ VNI 2000 ─ Eth8 │
└──┬──────────────────┬───────┘                         └──┬─────────────────┬───────┘
   │eth2/Eth4         │eth3/Eth8                           │eth2/Eth4        │eth3/Eth8
   │                  │                                    │                 │
   │eth2              │eth2                                │eth2             │eth2
┌──┴──────────┐  ┌────┴────────┐                       ┌───┴─────────┐ ┌─────┴───────┐
│    PC1      │  │    PC3      │                       │    PC2      │ │    PC4      │
│10.100.1.1/24│  │10.200.1.1/24│                       │10.100.1.2/24│ │10.200.1.2/24│
│aa:aa:aa:aa: │  │bb:bb:bb:bb: │                       │aa:aa:aa:aa: │ │bb:bb:bb:bb: │
│      aa:01  │  │      bb:03  │                       │      aa:02  │ │      bb:04  │
└─────────────┘  └─────────────┘                       └─────────────┘ └─────────────┘

  Tenant A:  VLAN 100 / VNI 1000 / 10.100.1.0/24   →  PC1 ⇄ PC2
  Tenant B:  VLAN 200 / VNI 2000 / 10.200.1.0/24   →  PC3 ⇄ PC4
  Isolation: VNI 1000 and VNI 2000 are separate broadcast domains
```

## Prerequisites
- This example was successfully replicated on an **Ubuntu (24.04.2 LTS) WSL** instance in Windows
- [Docker](https://docs.docker.com/engine/install/)
- [ContainerLab](https://containerlab.dev/install/)
- [sshpass](https://www.cyberciti.biz/faq/noninteractive-shell-script-ssh-password-provider/)

**Files to inspect**

- Topology: [sonic-vpp-L3-BGPEVPN/sonic-vpp01.clab.yml](sonic-vpp-L3-BGPEVPN/sonic-vpp01.clab.yml)
- Launch script: [sonic-vpp-L3-BGPEVPN/run.sh](sonic-vpp-L3-BGPEVPN/run.sh)
- Interface helper: [sonic-vpp-L3-BGPEVPN/scripts/step1-interfaces.sh](sonic-vpp-L3-BGPEVPN/scripts/step1-interfaces.sh)
- Router configs and VXLAN commands: [sonic-vpp-L3-BGPEVPN/routers](sonic-vpp-L3-BGPEVPN/routers)

## Running the example
First, clone the repository so you have a local copy:

```bash
git clone https://github.com/PANTHEONtech/cnf-examples.git
```

To launch the example, simply execute the *run.sh* script within the folder you downloaded the example to:

```bash
cd /cnf-examples/sonic-vpp/sonic-vpp-L3-BGPEVPN
./run.sh
```

The run.sh script orchestrates the setup and configuration of the VXLAN environment.

**Configuration flow**

The `run.sh` script performs these high-level actions:

1. Deploy the ContainerLab topology from `sonic-vpp01.clab.yml`
2. Configure host interfaces using `scripts/step1-interfaces.sh`
3. Apply FRR/`vtysh` configurations in `routers/*/*.vtysh` to establish BGP EVPN sessions
4. Apply VPP VXLAN commands in `routers/*/*-vxlan.cmd` to create VXLAN tunnels on each router

**Verification**

1. Start with topology and container checks (use `clab` first, fall back to `docker`):

```bash
clab inspect
docker ps
```

2. Check BGP peerings and EVPN routes

```bash
sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "vtysh -c 'show bgp summary'"
sshpass -p admin ssh admin@clab-sonic-vpp01-router2 "vtysh -c 'show bgp summary'"

sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "vtysh -c 'show bgp l2vpn evpn'"
sshpass -p admin ssh admin@clab-sonic-vpp01-router2 "vtysh -c 'show bgp l2vpn evpn'"
```

3. Check VXLAN interfaces on SONiC and VPP:

```bash
sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "show vxlan tunnel"
sshpass -p admin ssh admin@clab-sonic-vpp01-router2 "show vxlan tunnel"

sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "docker exec syncd vppctl show vxlan tunnel"
sshpass -p admin ssh admin@clab-sonic-vpp01-router2 "docker exec syncd vppctl show vxlan tunnel"
```

4. Test L2 connectivity between PCs (run from host with `clab exec`):

```bash
docker exec clab-sonic-vpp01-PC1 ping -c 5 168.95.10.1
```

5. To stop and destroy the example, simply execute the *stop.sh* script within the folder you downloaded the example to:

```bash
./stop.sh
```

## Packet tracing

To trace packets in VPP on Router1:

```bash
sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "docker exec syncd vppctl trace add dpdk-input 10"
# Generate traffic (from PC1):
docker exec clab-sonic-vpp01-PC1 ping -c 5 168.95.10.1
# View trace results:
sshpass -p admin ssh admin@clab-sonic-vpp01-router1 "docker exec syncd vppctl show trace"
```

# About

Learn more about [SONiC](https://pantheon.tech/services/expertise/sonic-nos/) and [how to orchestrate it](https://pantheon.tech/products/sandwork/).

Explore our other [SONiC-VPP examples in this repo](https://github.com/PANTHEONtech/cnf-examples/tree/master/sonic-vpp). 
