nv unset interface eth0 ip address dhcp
nv set interface eth0 ip address 10.10.2.32/22
nv set interface eth0 ip gateway 10.10.3.254

nv set interface lo ip address 10.10.7.218/32
nv set interface lo type loopback

nv set interface swp1-64 type swp

nv set interface vlan101 ip address 10.10.7.1/25

nv set router bgp autonomous-system 65182
nv set router bgp enable on
nv set router bgp router-id 10.10.7.218

nv set system hostname leaf02

nv set vrf default router bgp address-family ipv4-unicast enable on
nv set vrf default router bgp address-family ipv4-unicast redistribute connected enable on
nv set vrf default router bgp address-family ipv6-unicast enable on
nv set vrf default router bgp enable on
nv set vrf default router bgp neighbor swp1 peer-group UPLINK
nv set vrf default router bgp neighbor swp1 type unnumbered
nv set vrf default router bgp neighbor swp2 peer-group UPLINK
nv set vrf default router bgp neighbor swp2 type unnumbered
nv set vrf default router bgp neighbor swp3 peer-group UPLINK
nv set vrf default router bgp neighbor swp3 type unnumbered
nv set vrf default router bgp neighbor swp4 peer-group UPLINK
nv set vrf default router bgp neighbor swp4 type unnumbered
nv set vrf default router bgp neighbor swp5 peer-group UPLINK
nv set vrf default router bgp neighbor swp5 type unnumbered
nv set vrf default router bgp neighbor swp6 peer-group UPLINK
nv set vrf default router bgp neighbor swp6 type unnumbered
nv set vrf default router bgp neighbor swp7 peer-group UPLINK
nv set vrf default router bgp neighbor swp7 type unnumbered
nv set vrf default router bgp neighbor swp8 peer-group UPLINK
nv set vrf default router bgp neighbor swp8 type unnumbered
nv set vrf default router bgp neighbor swp9 peer-group UPLINK
nv set vrf default router bgp neighbor swp9 type unnumbered
nv set vrf default router bgp neighbor swp10 peer-group UPLINK
nv set vrf default router bgp neighbor swp10 type unnumbered
nv set vrf default router bgp neighbor swp11 peer-group UPLINK
nv set vrf default router bgp neighbor swp11 type unnumbered
nv set vrf default router bgp neighbor swp12 peer-group UPLINK
nv set vrf default router bgp neighbor swp12 type unnumbered
nv set vrf default router bgp neighbor swp13 peer-group UPLINK
nv set vrf default router bgp neighbor swp13 type unnumbered
nv set vrf default router bgp neighbor swp14 peer-group UPLINK
nv set vrf default router bgp neighbor swp14 type unnumbered
nv set vrf default router bgp neighbor swp15 peer-group UPLINK
nv set vrf default router bgp neighbor swp15 type unnumbered
nv set vrf default router bgp path-selection multipath aspath-ignore on
nv set vrf default router bgp peer-group UPLINK bfd enable on
nv set vrf default router bgp peer-group UPLINK remote-as external

nv config apply
nv config save

