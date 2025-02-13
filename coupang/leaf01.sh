nv unset interface eth0 ip address 10.10.2.29/22
nv set interface eth0 ip address 10.10.2.31/22
nv unset interface lo ip address 10.10.7.215/32

nv set interface swp1-64 type swp

nv set vrf default router bgp address-family ipv4-unicast redistribute connected enable on
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
nv set vrf default router bgp neighbor swp16 peer-group UPLINK
nv set vrf default router bgp neighbor swp16 type unnumbered
nv set vrf default router bgp neighbor swp17 peer-group UPLINK
nv set vrf default router bgp neighbor swp17 type unnumbered
nv set vrf default router bgp neighbor swp18 peer-group UPLINK
nv set vrf default router bgp neighbor swp18 type unnumbered
nv set vrf default router bgp neighbor swp19 peer-group UPLINK
nv set vrf default router bgp neighbor swp19 type unnumbered
nv set vrf default router bgp neighbor swp20 peer-group UPLINK
nv set vrf default router bgp neighbor swp20 type unnumbered
nv set vrf default router bgp neighbor swp21 peer-group UPLINK
nv set vrf default router bgp neighbor swp21 type unnumbered
nv set vrf default router bgp path-selection multipath aspath-ignore on
nv set vrf default router bgp peer-group UPLINK bfd enable on
nv set vrf default router bgp peer-group UPLINK remote-as external

nv config apply
nv config save


