#!/bin/bash

# Make sure curl is installed
apt-get -qq update
apt -qqy install curl
clear

TARBALLURL="https://github.com/coriumplatform/corium/releases/download/2.6.13/corium-2.6.13-linux64.tar.gz"
TARBALLNAME="corium-2.6.13-linux64.tar.gz"
MLDNVERSION="2.6.13"

clear
echo "This script will update your masternode to version $MLDNVERSION"
read -p "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root."
  exit 1
fi

USER=`ps u $(pgrep coriumd) | grep coriumd | cut -d " " -f 1`
USERHOME=`eval echo "~$USER"`

echo "Shutting down masternode..."
if [ -e /etc/systemd/system/coriumd.service ]; then
  systemctl stop coriumd
else
  su -c "corium-cli stop" $USER
fi

echo "Installing Corium $MLDNVERSION..."
mkdir ./corium-temp && cd ./corium-temp
wget $TARBALLURL
tar -xzvf $TARBALLNAME && mv bin corium-$MLDNVERSION
yes | cp -rf ./corium-$MLDNVERSION/coriumd /usr/local/bin
yes | cp -rf ./corium-$MLDNVERSION/corium-cli /usr/local/bin
cd ..
rm -rf ./corium-temp

if [ -e /usr/bin/coriumd ];then rm -rf /usr/bin/coriumd; fi
if [ -e /usr/bin/corium-cli ];then rm -rf /usr/bin/corium-cli; fi
if [ -e /usr/bin/corium-tx ];then rm -rf /usr/bin/corium-tx; fi

# Remove addnodes from corium.conf
sed -i '/^addnode/d' $USERHOME/.corium/corium.conf

# Add Fail2Ban memory hack if needed
if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
  echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
  systemctl restart fail2ban
fi

echo "Restarting Corium daemon..."
if [ -e /etc/systemd/system/coriumd.service ]; then
  systemctl disable coriumd
  rm /etc/systemd/system/coriumd.service
fi

cat > /etc/systemd/system/coriumd.service << EOL
[Unit]
Description=Coriums's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${USERHOME}
ExecStart=/usr/local/bin/coriumd -conf=${USERHOME}/.corium/corium.conf -datadir=${USERHOME}/.corium
ExecStop=/usr/local/bin/corium-cli -conf=${USERHOME}/.corium/corium.conf -datadir=${USERHOME}/.corium stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable coriumd
sudo systemctl start coriumd

sleep 10

clear

if ! systemctl status coriumd | grep -q "active (running)"; then
  echo "ERROR: Failed to start coriumd. Please contact support."
  exit
fi

echo "Waiting for wallet to load..."
until su -c "corium-cli getinfo 2>/dev/null | grep -q \"version\"" $USER; do
  sleep 1;
done

clear

echo "Your masternode is syncing. Please wait for this process to finish."
echo "This can take up to a few hours. Do not close this window."
echo ""

until su -c "corium-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  echo -ne "Current block: "`su -c "corium-cli getinfo" $USER | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

clear

cat << EOL

Now, you need to start your masternode. If you haven't already, please add this
node to your masternode.conf now, restart and unlock your desktop wallet, go to
the Masternodes tab, select your new node and click "Start Alias."

EOL

read -p "Press Enter to continue after you've done that. " -n1 -s

clear

su -c "corium-cli masternode status" $USER

cat << EOL

Masternode update completed.

EOL
