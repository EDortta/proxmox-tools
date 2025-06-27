# Tools

`create-vct.sh` Creates a container with a standard Debian configuration

`view-ips.sh` Shows the IPs of each container

`console.sh` Enters directly into the container

`clone-deve-ct-codium.sh` Clones a container

## Example
Creation of a base template from Debian and subsequent use of the same

This example covers the entire process of creating a light container inside Proxmox, with an IP in the VPN network (`192.168.2.x`), starting from a standard Debian template. The goal is to host a web server accessible by the name `interno.gestaox...com.br`.

### 1. Create the base container with `create-vct.sh`

Create a Debian 12 container with minimal resources for later installation of the web server:

```bash
./create-vct.sh --template debian-12-standard_12.7-1_amd64.tar.zst --ram 512 --disk 4 --cores 1
```

### 2. Convert the container to a template
If the CTID is 115, for example, you can do it like this:

```bash
pct stop 115
pct template 115
```

### 3. Clone the template
The idea here is to show how to clone it. In production, this will be necessary to scale the system. In this example, it doesn't make much sense.

Suppose the template is number 115, it goes like this:

```bash
VMID=$(pvesh get /cluster/nextid)
pct clone 115 $VMID --hostname interno-$VMID
```

When it finishes cloning, you can turn it on like this:
```bash
pct start $VMID
```

### 4. Resize the disk to 20GB

```bash
pct resize $VMID rootfs +16G
pct exec $VMID -- resize2fs /dev/mapper/devicename  # Replace with the real device if necessary
```

### 5. Set the IP
As it is, the container takes an IP from the 192.168.2.x network.

We will take this IP and set it in the cloned configuration

```bash
ip=$(pct exec "$VMID" -- hostname -I | awk '{print $1}')

pct set "$VMID" --net0 name=eth0,bridge=$DEFAULT_BRIDGE,ip=${ip}/24,gw=192.168.2.2,ip6=auto,firewall=1

pct set "$VMID" --net1 name=eth1,bridge=vmbr1,ip=172.18.32.$((VMID - 100))/24,firewall=1
```

### 6. Confirm that the IP is correct
For example, if it cloned 115 with number 116, it would look like this:
```bash
./view-ips.sh

VMID    Hostname           Ext.IP       Int.IP
...
116     interno-116        192.168.2.45 172.18.32.16
...
```

# config.json
The file `config.json` is a configuration file in JSON format and has the following format:

```json
{
    "ctid": {
        "containers": 200,
        "templates": 100
    },
    "network": {
        "bridge": {
            "net": "net0",
            "name": "eth0",
            "bridge": "vmbr2",
            "gateway": "192.168.2.2",
            "mask": "24",
            "dns": "8.8.8.8"
        },
        "nat": {
            "bridge": "vmbr1",
            "net": "net1",
            "name": "eth1",
            "base": "172.18.32.0",
            "mask": "24"
        }
    }
}
```