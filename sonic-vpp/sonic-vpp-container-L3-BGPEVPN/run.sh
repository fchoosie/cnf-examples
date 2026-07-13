#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker (https://docs.docker.com/engine/install/) and try again."
    exit 1
fi

# Check if clab is installed
if ! command -v clab &> /dev/null; then
    echo "Containerlab is not installed. Please install Containerlab (https://containerlab.dev/install/) and try again."
    exit 1
fi

# Check if the user is part of the docker group
if ! groups $USER | grep -q '\bdocker\b'; then
    echo "You are not a member of the docker group. Please add yourself to the docker group using:"
    echo "sudo usermod -aG docker $USER"
    echo "Then log out and back in for the changes to take effect."
    exit 1
fi

# Pull the single-container SONiC-VPP image if it isn't present locally.
SONIC_VPP_IMAGE="ghcr.io/mmiklus/docker-sonic-vpp:260710"
if ! docker image inspect "$SONIC_VPP_IMAGE" &> /dev/null; then
    echo "Pulling $SONIC_VPP_IMAGE..."
    if ! docker pull "$SONIC_VPP_IMAGE"; then
        echo "Failed to pull $SONIC_VPP_IMAGE. Check registry access and try again."
        exit 1
    fi
fi

set -x

# This variant uses the single-container SONiC-VPP image, where all SONiC
# processes (including VPP) run in one namespace. We therefore drive the
# routers directly with 'docker exec' instead of SSH.
ROUTER1="sudo docker exec -i clab-sonic-vpp01-router1"
ROUTER2="sudo docker exec -i clab-sonic-vpp01-router2"

if ! sudo clab deploy --topo sonic-vpp01.clab.yml; then
    { set +x; } > /dev/null 2>&1
    echo "Alternatively, you can manually destroy the existing containers using 'sudo clab destroy --topo sonic-vpp01.clab.yml' and rerun this script."
    exit 1
fi


# Wait for SONiC (and the VPP dataplane) to come up inside each container.
# The single-container image ships no docker healthcheck, so instead of
# waiting for a 'healthy' status we probe the routers functionally.

RETRY_INTERVAL=10  # seconds
MAX_RETRIES=30

router_ready() {
    # Ready when VPP answers, SONiC exposes its interface table and
    # vtysh can talk to bgpd (FRR fully up, so BGP config won't be lost).
    sudo docker exec clab-sonic-vpp01-"$1" vppctl show version >/dev/null 2>&1 \
        && sudo docker exec clab-sonic-vpp01-"$1" show interfaces status >/dev/null 2>&1 \
        && sudo docker exec clab-sonic-vpp01-"$1" vtysh -c 'show daemons' 2>/dev/null | grep -qw bgpd
}

for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "Attempt $i of $MAX_RETRIES..."

    if router_ready router1 && router_ready router2; then
        echo "Success: both routers are ready. Continuing..."
        break
    else
        echo "Routers not ready yet. Waiting..."
        if [ "$i" -eq "$MAX_RETRIES" ]; then
            echo "Error: Timeout reached. Routers did not become ready."
            exit 1
        fi
        sleep $RETRY_INTERVAL
    fi
done

set_swss_log_level() {
    $1 swssloglevel -l ERROR -a
    $1 swssloglevel -l SAI_LOG_LEVEL_INFO -s -a
}

set_swss_log_level "$ROUTER1"
set_swss_log_level "$ROUTER2"

./scripts/step1-interfaces.sh

execute() {
  local host=$1
  local file=$2

  if [[ "$file" == *.vtysh ]]; then
    # Send all commands in the file to vtysh via a heredoc inside the container
    $1 bash <<EOF
vtysh <<EOV
$(cat "$file")
EOV
EOF

  else
    # Handle line-by-line CLI commands (run each through a shell in the container)
    mapfile -t commands < "$file"
    for cmd in "${commands[@]}"; do
      $1 sh -c "$cmd"
    done
  fi
}

# Apply a vtysh config file and verify it actually landed in the running
# config, retrying if not. On a freshly booted SONiC, bgpcfgd may still be
# regenerating the FRR config and wipe changes applied too early.
apply_vtysh_verified() {
  local host=$1
  local file=$2
  local check=$3   # string that must appear in 'show running-config'
  local attempt

  for attempt in 1 2 3 4 5; do
    execute "$host" "$file"
    sleep 3
    if $host vtysh -c 'show running-config' 2>/dev/null | grep -q "$check"; then
      echo "Verified: '$check' present in running config."
      return 0
    fi
    echo "Config from $file not present yet (attempt $attempt of 5), retrying..."
    sleep 5
  done

  echo "Error: could not verify config from $file ('$check' missing)."
  return 1
}

sleep 5

apply_vtysh_verified "$ROUTER1" "routers/router1/r1-1.vtysh" "neighbor 10.0.1.0 remote-as 65100"
apply_vtysh_verified "$ROUTER2" "routers/router2/r2-1.vtysh" "neighbor 10.0.1.1 remote-as 65100"

sleep 5

execute "$ROUTER1" "routers/router1/r1-vxlan.cmd"
execute "$ROUTER2" "routers/router2/r2-vxlan.cmd"

sleep 5

# The single-container image keeps a kernel-native VXLAN bridge (used by
# SONiC's CLI/config state) alongside VPP's own dataplane bridge. Both are
# live, so without this every bridged frame gets forwarded twice (visible
# as DUP! replies in ping). VPP already handles the real dataplane, so
# stop the kernel bridge from re-flooding traffic out its access ports.
disable_kernel_bridge_flood() {
  local host=$1
  local ports
  ports=$($host sh -c 'bridge -j link show master Bridge 2>/dev/null' | grep -o '"ifname":"Ethernet[0-9]*"' | cut -d'"' -f4)
  for p in $ports; do
    $host sh -c "bridge link set dev $p flood off"
  done
}

disable_kernel_bridge_flood "$ROUTER1"
disable_kernel_bridge_flood "$ROUTER2"

apply_vtysh_verified "$ROUTER1" "routers/router1/r1-2.vtysh" "neighbor 10.0.1.0 activate"
apply_vtysh_verified "$ROUTER2" "routers/router2/r2-2.vtysh" "neighbor 10.0.1.1 activate"
