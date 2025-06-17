
pct create 100 local-btrfs:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst   --hostname ghostbridge --memory 8096 --cores 2 --rootfs local-btrfs:20  --net0 name=eth0,bridge=vmbr0,ip=10.0.0.151/24,gw=10.0.0.1 --net1  name=eth1,bridge=vmbr0,ip=80.209.240.244/25,gw=80.209.240.129  --nameserver 8.8.8.8 --nameserver 8.8.4.4 --features nesting=1  --unprivileged 1 --onboot 1
