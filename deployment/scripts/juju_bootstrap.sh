#!/bin/bash
[ $(lsb_release -sc) != 'noble' ] && { echo 'ERROR: Sunbeam deploy only supported on noble'; exit 1; }

# ⚠ Node Preparation for OpenStack Sunbeam ⚠
# All of these commands perform privileged operations
# please review carefully before execution.
USER=$(whoami)

if [ $(id -u) -eq 0 -o "$USER" = root ]; then
    cat << EOF
ERROR: Node Preparation script for OpenStack Sunbeam must be executed by
       non-root user with sudo permissions.
EOF
    exit 1
fi

# Check if user has passwordless sudo permissions and setup if need be
SUDO_ASKPASS=/bin/false sudo -A whoami &> /dev/null &&
sudo grep -r $USER /etc/{sudoers,sudoers.d} | grep NOPASSWD:ALL &> /dev/null || {
    echo "$USER ALL=(ALL) NOPASSWD:ALL" > /tmp/90-$USER-sudo-access
    sudo install -m 440 /tmp/90-$USER-sudo-access /etc/sudoers.d/90-$USER-sudo-access
    rm -f /tmp/90-$USER-sudo-access
}

# Ensure dependency packages are installed
for pkg in openssh-server curl sed; do
    dpkg -s $pkg &> /dev/null || {
        sudo apt install -y $pkg
    }
done

# Add $USER to the snap_daemon group supporting interaction
# with the sunbeam clustering daemon for cluster operations.
sudo usermod --append --groups snap_daemon $USER

# Generate keypair and set-up prompt-less access to local machine
[ -f $HOME/.ssh/id_ed25519 ] || ssh-keygen -f $HOME/.ssh/id_ed25519 -t ed25519 -N ""
cat $HOME/.ssh/id_ed25519.pub >> $HOME/.ssh/authorized_keys
ssh-keyscan -H $(hostname --all-ip-addresses) >> $HOME/.ssh/known_hosts

if ! grep -E 'HTTPS?_PROXY' /etc/environment &> /dev/null && ! curl -s -m 10 -x "" api.charmhub.io &> /dev/null; then
    cat << EOF
ERROR: No external connectivity. Set HTTP_PROXY, HTTPS_PROXY, NO_PROXY
       in /etc/environment and re-run this command.
EOF
    exit 1
fi

if grep -E -q 'HTTPS?_PROXY=' /etc/environment; then
    echo "Loading in current shell environment variables from /etc/environment"
    source /etc/environment
fi

# Ensure the localhost IPs are present in the no_proxy list
# both on disk and in the environment
if grep -E -q 'NO_PROXY=' /etc/environment; then
    echo "Ensuring all localhost IPs are in the no_proxy list"
    for ip in $(hostname -I); do
        if [ -z "$NO_PROXY" ]; then
            echo "NO_PROXY is not set in current shell"
            export NO_PROXY="$ip"
        else
            export NO_PROXY="$NO_PROXY,$ip"
        fi
        grep -E -q "NO_PROXY=.*$ip.*" /etc/environment             || sudo sed -E -i                 -e "s|^NO_PROXY=\"+(.*)\"+|NO_PROXY=\"\1,$ip\"|"                 -e "s|^NO_PROXY=\",|NO_PROXY=\"|"                     /etc/environment
    done
fi

# Connect snap to the ssh-keys interface to allow
# read access to private keys - this supports bootstrap
# of the Juju controller to the local machine via SSH.
# This also gives access to the ssh binary to the snap.
sudo snap connect openstack:ssh-keys

# Install the Juju snap
sudo snap install --channel 3.6/stable juju

# Workaround a bug between snapd and juju
mkdir -p $HOME/.local/share
mkdir -p $HOME/.config/openstack

# Check the snap channel and deduce risk level from it
snap_output=$(snap list openstack --unicode=never --color=never | grep openstack)
track=$(awk -v col=4 '{print $col}' <<<"$snap_output")

# if never installed from the store, the channel is "-"
if [[ $track =~ "edge" ]] || [[ $track == "-" ]]; then
    risk="edge"
elif [[ $track =~ "beta" ]]; then
    risk="beta"
elif [[ $track =~ "candidate" ]]; then
    risk="candidate"
else
    risk="stable"
fi

if [[ $risk != "stable" ]]; then
    sudo snap set openstack deployment.risk=$risk
    echo "Snap has been automatically configured to deploy from"         "$risk channel."
    echo "Override by passing a custom manifest with -m/--manifest."
fi

# Install the lxd snap
sudo snap install lxd --channel 5.21/stable
USER=$(whoami)
# Ensure current user is part of the LXD group
sudo usermod --append --groups lxd $USER

if [ -n "$(sudo --user $USER lxc network list --format csv | grep lxdbr0)" ]; then
    echo 'Sunbeam requires the LXD bridge to be called anything except lxdbr0'
    exit 1
fi

# Try to determine if LXD is already bootstrapped
if [ -z "$(sudo --user $USER lxc storage list --format csv)" ];
then
    echo 'Bootstrapping LXD'
    cat <<EOF | sudo --user $USER lxd init --preseed
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  name: sunbeambr0
  project: default
storage_pools:
- name: default
  driver: dir
profiles:
- devices:
    eth0:
      name: eth0
      network: sunbeambr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF
fi

# Add the LXD bridges to the no_proxy list while we don't know the container IP
if grep -E -q 'HTTPS?_PROXY=' /etc/environment; then
    cidr=$(sudo --user $USER lxc network list --format compact | grep YES | col4 |         tr '\n' ',')
    export NO_PROXY="$(echo $NO_PROXY,$cidr | sed -e 's|^,||' -e 's|,$||')"
fi

# Bootstrap juju onto LXD
echo 'Bootstrapping Juju onto LXD'
sudo --user $USER juju show-controller 2>/dev/null
if [ $? -ne 0 ]; then
    set -e
    if printenv | grep -q "^HTTP_PROXY"; then
        sudo --preserve-env --user $USER juju download juju-controller \
            --channel 3.6/stable --base ubuntu@24.04
        mv juju-controller_r*.charm juju-controller.charm
        sudo --preserve-env --user $USER juju bootstrap localhost \
            --controller-charm-path=juju-controller.charm \
            --config "juju-http-proxy=$HTTP_PROXY" \
            --config "juju-https-proxy=$HTTPS_PROXY" \
            --config "juju-no-proxy=$NO_PROXY" \
            --config "no-proxy=$NO_PROXY" \
            --config "snap-http-proxy=$HTTP_PROXY" \
            --config "snap-https-proxy=$HTTPS_PROXY" \
            --model-default "juju-http-proxy=$HTTP_PROXY" \
            --model-default "juju-https-proxy=$HTTPS_PROXY" \
            --model-default "juju-no-proxy=$NO_PROXY" \
            --model-default "no-proxy=$NO_PROXY" \
            --model-default "snap-http-proxy=$HTTP_PROXY" \
            --model-default "snap-https-proxy=$HTTPS_PROXY"
        rm juju-controller.charm
        controller=$(sudo --user $USER lxc list --format compact | grep juju- | col3)
        echo "Ensuring Controller ip '$controller' is in the no_proxy list"
        grep -E -q "NO_PROXY=.*$controller.*" /etc/environment             || sudo sed -E                 -i "s|^NO_PROXY=\"+(.*)\"+|NO_PROXY=\"\1,$controller\"|"                 /etc/environment
        sleep 10
        sudo --preserve-env --user $USER juju refresh --model controller \
            controller --switch ch:juju-controller --channel 3.6/stable
        sudo --preserve-env --user $USER juju switch admin/controller
        sudo --preserve-env --user $USER juju wait-for application controller
        sudo --preserve-env --user $USER juju wait-for unit controller/0 \
            --query 'life=="alive"'
    else
        sudo --user $USER juju bootstrap localhost
    fi
    echo "Juju bootstrap complete, you can now bootstrap sunbeam!"
fi
