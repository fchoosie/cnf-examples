# SONiC-VPP L3 BGP EVPN (single-container variant)

This example demonstrates the integration of a high-performance software data plane ([VPP](https://fd.io/)) with a standardized network operating system ([SONiC](https://sonicfoundation.dev/)) to run advanced data center fabric protocols ([BGP EVPN](https://pantheon.tech/blog-news/what-is-bgp-evpn/)).

You will see a 2-site EVPN-VXLAN lab using **SONiC** + **VPP** data plane. The lab shows how: 
- **BGP EVPN** routes are signaled between two router nodes
- How VPP-created VXLAN tunnels forward L2 traffic so remote PCs appear on the same L2 VNI

> **Difference from [sonic-vpp-L3-BGPEVPN](../sonic-vpp-L3-BGPEVPN):**
> That example runs the `sonic-vm` ContainerLab kind, where SONiC boots inside a
> QEMU VM that itself hosts nested Docker containers (VPP runs in the `syncd`
> container, reached via `docker exec syncd vppctl`).
> This variant uses the single-container `docker-sonic-vpp` image
> (ContainerLab `linux` kind, following the same pattern as
> [vpp-vxlan](../../vpp-vxlan)): **all SONiC processes, including VPP, run in a
> single namespace**. As a result VPP is reached directly with `vppctl`, and the
> routers are driven with `docker exec` instead of SSH.
>
> One consequence of sharing a namespace: SONiC's `config vlan`/`config vxlan`
> commands also stand up a kernel-native VXLAN bridge alongside VPP's own
> dataplane bridge. Both are live, so without mitigation every bridged frame
> is forwarded twice (visible as `DUP!` replies in `ping`). `run.sh`/`run2.sh`
> disable flooding on the kernel bridge's access ports right after the VXLAN
> config step to stop this; VPP's own forwarding path is unaffected.

## Prerequisites
- [Docker](https://docs.docker.com/engine/install/)
- [ContainerLab](https://containerlab.dev/install/)
- The single-container SONiC-VPP image `ghcr.io/mmiklus/docker-sonic-vpp:260710`. `run.sh`/`run2.sh` pull it automatically if it isn't present locally; to fetch it manually:

```bash
docker pull ghcr.io/mmiklus/docker-sonic-vpp:260710
```

**Files to inspect**

- Topology: [sonic-vpp01.clab.yml](sonic-vpp01.clab.yml)
- Launch script: [run.sh](run.sh)
- Interface helper: [scripts/step1-interfaces.sh](scripts/step1-interfaces.sh)
- Router configs and VXLAN commands: [routers](routers)

## Running the example
First, clone the repository so you have a local copy:

```bash
git clone https://github.com/PANTHEONtech/cnf-examples.git
```

To launch the example, simply execute the *run.sh* script within the folder you downloaded the example to:

```bash
cd /cnf-examples/sonic-vpp/sonic-vpp-container-L3-BGPEVPN
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
sudo docker exec clab-sonic-vpp01-router1 vtysh -c 'show bgp summary'
sudo docker exec clab-sonic-vpp01-router2 vtysh -c 'show bgp summary'

sudo docker exec clab-sonic-vpp01-router1 vtysh -c 'show bgp l2vpn evpn'
sudo docker exec clab-sonic-vpp01-router2 vtysh -c 'show bgp l2vpn evpn'
```

3. Check VXLAN interfaces on SONiC and VPP:

```bash
sudo docker exec clab-sonic-vpp01-router1 show vxlan tunnel
sudo docker exec clab-sonic-vpp01-router2 show vxlan tunnel

sudo docker exec clab-sonic-vpp01-router1 vppctl show vxlan tunnel
sudo docker exec clab-sonic-vpp01-router2 vppctl show vxlan tunnel
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
sudo docker exec clab-sonic-vpp01-router1 vppctl trace add dpdk-input 10
# Generate traffic (from PC1):
docker exec clab-sonic-vpp01-PC1 ping -c 5 168.95.10.1
# View trace results:
sudo docker exec clab-sonic-vpp01-router1 vppctl show trace
```

# About

Learn more about [SONiC](https://pantheon.tech/services/expertise/sonic-nos/) and [how to orchestrate it](https://pantheon.tech/products/sandwork/).

Explore our other [SONiC-VPP examples in this repo](https://github.com/PANTHEONtech/cnf-examples/tree/master/sonic-vpp). 
