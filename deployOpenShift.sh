#!/bin/bash

set -e

SUDOUSER=$1
PASSWORD=$2
PUBLICKEY=$3
PRIVATEKEY=$4
MASTER=$5
MASTERPUBLICIPHOSTNAME=$6
MASTERPUBLICIPADDRESS=$7
NODEPREFIX=$8
NODECOUNT=$9

DOMAIN=$( awk 'NR==2' /etc/resolv.conf | awk '{ print $2 }' )

# Generate public / private keys for use by Ansible

echo "Generating keys"

# runuser -l $SUDOUSER -c "echo \"$PUBLICKEY\" > ~/.ssh/id_rsa.pub"
runuser -l $SUDOUSER -c "echo \"$PRIVATEKEY\" > ~/.ssh/id_rsa"
runuser -l $SUDOUSER -c "chmod 600 ~/.ssh/id_rsa*"

echo "Configuring SSH ControlPath to use shorter path name"

# sed -i -e "s/^# control_path = %(directory)s\/%%h-%%r/control_path = %(directory)s\/%%h-%%r/" /etc/ansible/ansible.cfg
# sed -i -e "s/^#host_key_checking = False/host_key_checking = False/" /etc/ansible/ansible.cfg
# sed -i -e "s/^#pty=False/pty=False/" /etc/ansible/ansible.cfg

# Generating Installer File

echo "Generating Installer File"

echo "ansible_config: /usr/share/atomic-openshift-utils/ansible.cfg" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
cat > $SUDOUSER/home/.config/openshift/installer.cfg.yml<<EOF
ansible_log_path: /tmp/ansible.log
ansible_ssh_user: $SUDOUSER
hosts:
- connect_to: $MASTER
  hostname: $MASTER.$DOMAIN
  master: true
  node: true
  public_hostname: $MASTERPUBLICIPHOSTNAME
  public_ip: $MASTERPUBLICIPADDRESS
  storage: true
EOF

for (( c=0; c<$NODECOUNT; c++ ))
do
  echo "- connect_to: $NODEPREFIX-$c" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
  echo "hostname: $NODEPREFIX-$c.$DOMAIN" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
  echo "node: true" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
done

echo "variant: openshift-enterprise" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
echo "variant_version: '3.2'" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml
echo "version: v1" >> $SUDOUSER/home/.config/openshift/installer.cfg.yml

mkdir -p /etc/origin/master
htpasswd -cb /etc/origin/master/htpasswd ${SUDOUSER} ${PASSWORD}

# Executing OpenShift Atomic Installer

echo "Executing OpenShift Atomic Installer"

runuser -l $SUDOUSER -c "atomic-openshift-installer -u install"

echo "Modifying sudoers"

sed -i -e "s/Defaults    requiretty/# Defaults    requiretty/" /etc/sudoers
sed -i -e '/Defaults    env_keep += "LC_TIME LC_ALL LANGUAGE LINGUAS _XKB_CHARSET XAUTHORITY"/aDefaults    env_keep += "PATH"' /etc/sudoers

echo "Deploying Registry"

runuser -l $SUDOUSER -c "sudo oadm registry --config=/etc/origin/master/admin.kubeconfig --credentials=/etc/origin/master/openshift-registry.kubeconfig"

echo "Deploying Router"

runuser -l $SUDOUSER -c "sudo oadm router osrouter --replicas=$NODECOUNT --credentials=/etc/origin/master/openshift-router.kubeconfig --service-account=router"

echo "Re-enabling requiretty"

sed -i -e "s/# Defaults    requiretty/Defaults    requiretty/" /etc/sudoers