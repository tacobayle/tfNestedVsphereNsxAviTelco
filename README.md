# tfNestedVsphereNsxAviTelco

## Goal

This Infrastructure as code will deploy a nested ESXi/vCenter/NSX/TKG/Avi (on the top of vCenter environment which does not support 802.1q or vlan tagged).
The goal is to build a demo to demonstrate the BGP capabilities of Avi/AKO with the NSX tier0s:
- reliability
- scalability
- flexibility - with the BGP label to control to which BGP peer (VRF) a VIP will be advertised to
- visibility

## variables

### non sensitive variables

All the non-sensitive variables are stored in variables.json

### sensitive variables

All the sensitive variables are stored in environment variables as below:

```bash
export TF_VAR_esxi_root_password=******              # Nested ESXi root password
export TF_VAR_vsphere_username=******                # Underlay vCenter username
export TF_VAR_vsphere_password=******                # Underlay vCenter password
export TF_VAR_bind_password=******                   # Bind password
export TF_VAR_ubuntu_password=******                 # Ubuntu password for dns-ntp and external gw VMs
export TF_VAR_vcenter_password=******                # Overlay vCenter admin password
export TF_VAR_nsx_password=******                    # NSX admin password
export TF_VAR_nsx_license=******                     # NSX license
export TF_VAR_avi_password=******                    # AVI admin password
export TF_VAR_avi_old_password=******                # AVI old passwords
export TF_VAR_docker_registry_password=******        # docker password
export TF_VAR_docker_registry_username=******        # docker username
```

vCenter Password constraints:

```
The entered password for new_vcsa os password does not meet the requirements because it violates password policy.
Password must conform to the following requirements: 
At least 8 characters No more than 20 characters
At least 1 uppercase character
At least 1 lowercase character
At least 1 number
At least 1 special character (e.g., '!', '(', '@', etc.)
Only visible A-Z, a-z, 0-9 and punctuation (spaces are not allowed)
```

## underlay infrastructure

### tested against
- vCenter underlay version:
```
6.7.0
```

### Orchestrator OS and softwares
= OS
```shell
NAME="Ubuntu"
VERSION="20.04.3 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.3 LTS"
VERSION_ID="20.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=focal
UBUNTU_CODENAME=focal

```

- Terraform:
```
Terraform v1.0.6
on linux_amd64
```

- govc:
```
govc v0.24.0
```

- genisoimage:
```
genisoimage 1.1.11 (Linux)
```

- ansible
```
ansible [core 2.11.12]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/local/lib/python3.6/site-packages/ansible
  ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/local/bin/ansible
  python version = 3.6.8 (default, Nov 16 2020, 16:55:22) [GCC 4.8.5 20150623 (Red Hat 4.8.5-44)]
  jinja version = 3.0.3
  libyaml = True
```

- ansible collections
```
ansible-galaxy collection list | grep nsx
vmware.ansible_for_nsxt 1.0.0
```

```
ansible-galaxy collection list | grep vmware
community.vmware        2.5.0
```

- python module
```
pip3 list | grep pyvm
pyvmomi            7.0.3
```

### Files required to build the underlay VM(s)

- dns_ntp and external-gw:
  - "focal-server-cloudimg-amd64.ova defined" in "vcenter_underlay.cl.ubuntu_focal_file_path"  # can be downloaded here: https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.ova
- ESXi(s):
  - "VMware-VMvisor-Installer-7.0U3g-20328353.x86_64.iso" defined in vcenter_underlay.cl.ubuntu_focal_file_path # can be downloaded here: https://customerconnect.vmware.com

### VM(s)

On the top of an underlay/outer vCenter environment, this repo will create the following:

![img.png](imgs/img01.png)

### VM(s) connectivity

![img.png](imgs/underlay_architecture.png)

### Network details

The following variables need to be configured:

- For the management network (which needs to reach the Internet):
  - vcenter.dvs.portgroup.management.netmask like "255.255.252.0"
  - vcenter.dvs.portgroup.management.prefix like "22"
  - vcenter.dvs.portgroup.management.gateway like "10.41.132.1"
- For the VMotion network:
  - vcenter.dvs.portgroup.VMotion.netmask like "255.255.255.0"
  - vcenter.dvs.portgroup.VMotion.prefix like "24"
- For the vSAN network:
  - vcenter.dvs.portgroup.VSAN.netmask like "255.255.255.0"
  - vcenter.dvs.portgroup.VSAN.prefix like "24"

### VM(s) IPs

- For the management network, static IPs are configured as followed:
    - the ESXi VMs IPs are defined in vcenter.dvs.portgroup.management.esxi_ips[]
    - the ESXi VMs temporary IPs are defined in vcenter.dvs.portgroup.management.esxi_ips_temp - these IPs are released once the infra is ready
    - the dns_vm VM IP is defined in vcenter.dvs.portgroup.management.dns_ntp_ip
    - the external-gw VM IP is defined in vcenter.dvs.portgroup.management.external_gw_ip

- For the Vmotion network, static IPs are configured as followed:
    - the ESXi VMs IP are defined in vcenter.dvs.portgroup.VMotion.esxi_ips[]

- For the vSAN network, static IPs are configured as followed:
    - the ESXi VMs IP are defined in vcenter.dvs.portgroup.VSAN.esxi_ips[]

- For the NSX external network, static IPs are configured as followed:
    - the external-gw VM IP is defined in vcenter.dvs.portgroup.nsx_external.external_gw_ip

- For the NSX overlay network, static IPs are configured as followed:
    - the external-gw VM IP is defined in nsx.config.ip_pools[0].gateway

- For the NSX overlay edge network, static IPs are configured as followed:
    - the external-gw VM IP is defined in nsx.config.ip_pools[1].gateway

### VM(s) usage

- the dns_ntp VM is used as a DNS server (for A records and PTR records) for all the VM in the nested infrastructure
- the external-gw VM is used as:
  - an external gateway for traffic coming from the NSX Edge nodes to the Internet (this will source NAT the traffic)
  - a router between the transport nodes and the edge nodes for the overlay (Geneve traffic) 
- ESXi VM(s) will be the foundation of the nested infrastructure

## Nested infrastructure

### Files required to build the nested VM(s)

- vCenter:
  - "VMware-VCSA-all-7.0.3-20395099.iso" defined in "vcenter.iso_source_location"
- NSX Manager:
  - "nsx-unified-appliance-3.2.1.0.0.19801963.ova" defined in "nsx.content_library.ova_location"
- Avi Controller:
  - "controller-22.1.3-9096.ova" defined in "avi.content_library.ova_location"
- TKG files:
  - "tanzu-cli-bundle-linux-amd64.tar.gz" defined in "tkg.tanzu_bin_location"
  - "kubectl-linux-v1.23.8+vmware.2.gz" defined in tkg.k8s_bin_location
  - "ubuntu-2004-kube-v1.23.8+vmware.2-tkg.1-85a434f93857371fccb566a414462981.ova" defined in tkg.ova_location

### vCenter deployment




It will deploy a single vCenter on the top of the management port group (connected to the management network of the underlay infrastructure).
IP is defined in vcenter.dvs.portgroup.management.vcenter_ip.

Here is below the nested infrastructure created:

![img.png](imgs/nested_vcenter_overview.jpg)  

### vCenter configuration:

- networking (vds and port group)
- adding ESXi hosts
- vSAN
- ...
- NSX VDS(s) and port group(s):

![img.png](imgs/nested_vcenter_vds_pg.jpg)

### NSX Manager deployment

It will deploy a single NSX Manager on the top of the management PG (connected to the management network of the underlay infrastructure).
IP is defined in vcenter.dvs.portgroup.management.nsx_ip.

### NSX configuration:
- NSX license
- ip pools

![img.png](imgs/nested_nsx_ip_pools.jpg)  

- uplink profiles

![img.png](imgs/nested_nsx_uplink_profiles.jpg)

- transport node profiles

![img.png](imgs/nested_nsx_transport_node_profiles.jpg)

- transport zones

![img.png](imgs/nested_nsx_transport_zones.jpg)

- compute managers
- transport nodes

![img.png](imgs/nested_nsx_transport_nodes.jpg)

- edge transport nodes

![img.png](imgs/nested_nsx_edge_nodes.jpg)

- edge clusters

![img.png](imgs/nested_nsx_edge_clusters.jpg)  
- tier0(s):
  - interfaces
  - routing
  - HA VIP configuration

![img.png](imgs/nested_nsx_tier0s.jpg)
- tier1(s):
  - IP
  - route advertisement
  
![img.png](imgs/nested_nsx_tier1s.jpg)
- overlay segment(s):
  
![img.png](imgs/nested_nsx_segments.jpg)

### Avi controller deployment

It will deploy a single Avi controller on the top of the management overlay segment defined in nsx.config.segments_overlay[0].display_name.

### Avi controller configuration

- Bootstrap controller with password defined in environment variable (see below) 
- System parameters
- DNS profile
- IPAM profile
- vCenter Cloud
- VSVIP Config
- Pool config
- VS config

### TKG 

#### TKG management cluster


#### TKG workload cluster(s)



## start the script (create the infra)
```shell
/bin/bash apply.sh
```


## destroy the infra

```shell
/bin/bash destroy.sh
```
