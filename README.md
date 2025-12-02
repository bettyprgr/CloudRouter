# Cloud Router (alpha) v.0.1.0

### 1. Connect to the VPS

Use your provider’s console or SSH.

If SSH is not yet available, use the VPS provider’s **Recovery/Console** access.

Once you have a shell on the VPS, configure the `lan` interface to use DHCP so the system can obtain network connectivity:

    uci set network.lan.proto='dhcp'
    uci commit network
    ifup lan

After a few seconds the VPS should obtain an IP address from the provider and have internet connectivity.

---

### 2. Download and run the Init script

Download the script into `/root` using the **raw** GitHub URL (not the `blob` page), make it executable and run it:

    cd /root
    wget https://bit.ly/48pjhmD
    chmod +x init.sh
    sh init.sh
