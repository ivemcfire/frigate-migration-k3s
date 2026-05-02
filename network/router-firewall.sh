#!/bin/sh
# Re-applied at every router boot via cron @reboot or vendor startup hook.
# Stock firmware does not persist iptables rules, so anything we set in
# the GUI vanishes after a power cut.
#
# Goal: keep cameras isolated on their VLAN segment with no internet
# route, while letting the Frigate node reach them on RTSP/ONVIF.

CAM_SUBNET="192.168.X.0/24"        # camera VLAN
LAN_SUBNET="192.168.Y.0/24"        # main LAN
FRIGATE_NODE="192.168.Y.Z"          # k3frigate

# Drop all camera-originated traffic to the WAN
iptables -I FORWARD -s "$CAM_SUBNET" -o eth0.2 -j DROP

# Drop camera-originated traffic to other LAN segments
iptables -I FORWARD -s "$CAM_SUBNET" -d "$LAN_SUBNET" -j DROP

# Allow Frigate node to talk to cameras (RTSP, ONVIF)
iptables -I FORWARD -s "$FRIGATE_NODE" -d "$CAM_SUBNET" -j ACCEPT
iptables -I FORWARD -s "$CAM_SUBNET" -d "$FRIGATE_NODE" -j ACCEPT

# Block camera DNS lookups (most cameras will phone home if they can resolve)
iptables -I FORWARD -s "$CAM_SUBNET" -p udp --dport 53 -j DROP
iptables -I FORWARD -s "$CAM_SUBNET" -p tcp --dport 53 -j DROP
