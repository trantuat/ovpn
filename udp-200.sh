#!/bin/bash
#
# https://github.com/gayankuruppu/openvpn-install-for-multiple-users
# This script enables duplicate-cn in server.conf. You can share the same client.ovpn file for multiple users.
# Based on Nyr https://github.com/Nyr/openvpn-install
#
# checks if ubuntu is 1604

# checks the operating system version
if [[ -e /etc/debian_version ]]; then
	OS=debian
	GROUPNAME=nogroup
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
	GROUPNAME=nobody
else
	echo "This script only works on Debian, Ubuntu or CentOS"
	echo "Go to https://github.com/gayankuruppu/openvpn-install-for-multiple-users for FAQ"
	exit
fi

PORT=1200
DNS=1
PROTOCOL=udp
# Autodetect IP address and pre-fill for the user
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
read -p "IP address: " -e -i $IP IP
# If $IP is a private IP address, the server must be behind NAT
if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
	echo
	echo "Enter Public IPv4 Address"
	read -p "Public IP Address: " -e PUBLICIP
fi
# Generate server.conf
echo "port $PORT
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
duplicate-cn
auth SHA512
tls-auth ta.key 0
topology subnet
server 10.14.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt" > /etc/openvpn/server/server5.conf
	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server/server5.conf
	# DNS
	case $DNS in
		1)
		# Locate the proper resolv.conf
		# Needed for systems running systemd-resolved
		if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			RESOLVCONF='/run/systemd/resolve/resolv.conf'
		else
			RESOLVCONF='/etc/resolv.conf'
		fi
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' $RESOLVCONF | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server/server5.conf
		done
		;;
		2)
		echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server/server5.conf
		echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server/server5.conf
		;;
		3)
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server/server5.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server/server5.conf
		;;
		4)
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server/server5.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server/server5.conf
		;;
		5)
		echo 'push "dhcp-option DNS 64.6.64.6"' >> /etc/openvpn/server/server5.conf
		echo 'push "dhcp-option DNS 64.6.65.6"' >> /etc/openvpn/server/server5.conf
		;;
	esac
	echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $GROUPNAME
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem" >> /etc/openvpn/server/server5.conf
	echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A POSTROUTING -s 10.14.0.0/24 ! -d 10.14.0.0/24 -j SNAT --to $IP
ExecStart=/sbin/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -s 10.14.0.0/24 -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/sbin/iptables -t nat -D POSTROUTING -s 10.14.0.0/24 ! -d 10.14.0.0/24 -j SNAT --to $IP
ExecStop=/sbin/iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -s 10.14.0.0/24 -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/openvpn-iptables5.service
		
	systemctl enable --now openvpn-iptables5.service
	
	# And finally, enable and start the OpenVPN service
	systemctl enable --now openvpn-server@server5.service
