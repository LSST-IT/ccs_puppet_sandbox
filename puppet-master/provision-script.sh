#!/bin/bash

ENVIRONMENT=$1
IP=$2

rpm -Uvh https://yum.puppetlabs.com/puppet5/puppet5-release-el-7.noarch.rpm
yum install -y puppetserver git
sed -i 's#\-Xms2g#\-Xms512m#g;s#\-Xmx2g#\-Xmx512m#g' /etc/sysconfig/puppetserver
echo -e "certname = puppet-master.slac.stanford.edu" >> /etc/puppetlabs/puppet/puppet.conf
echo -e "\n[main]\nenvironment = production" >> /etc/puppetlabs/puppet/puppet.conf
echo -e "\n[agent]\nserver = puppet-master.slac.stanford.edu" >> /etc/puppetlabs/puppet/puppet.conf
echo -e "${IP}\tpuppet-master\tpuppet-master.slac.stanford.edu" > /etc/hosts

sed -i 's#^PATH=.*#PATH=$PATH:/opt/puppetlabs/puppet/bin:$HOME/bin#g' /root/.bash_profile
/opt/puppetlabs/puppet/bin/gem install r10k

if [ ! -d /etc/puppetlabs/r10k/ ]
then
	mkdir -p /etc/puppetlabs/r10k/
fi

if [ ! -d /etc/puppetlabs/code/hieradata/ ]
then
	mkdir -p /etc/puppetlabs/code/hieradata/production
fi

if [ -z "$(grep etc_puppetlabs_code_hieradata_production /etc/fstab)" ]
then
echo "etc_puppetlabs_code_hieradata_production /etc/puppetlabs/code/hieradata/production vboxsf defaults,ro 0 0" >> /etc/fstab
	mount -a
fi

echo -e "---
:cachedir: '/var/cache/r10k'

# Hiera repo not configured thru r10k since is leveraging a shared folder
:sources:
  :lsst.org:
    remote: 'https://github.com/lsst/itconf_l1ts.git'
    basedir: '/etc/puppetlabs/code/environments'
" > /etc/puppetlabs/r10k/r10k.yaml

/opt/puppetlabs/puppet/bin/r10k deploy environment -p

for f in $(ls -1 /etc/puppetlabs/code/environments/)
do
	echo "Found environment $f"
	if [ ! -d "/etc/puppetlabs/code/hieradata/$f" ]
	then
		echo "dir $f don't exists, creating it from production"
		ln -s /etc/puppetlabs/code/hieradata/production /etc/puppetlabs/code/hieradata/$f
	fi

  # Temporary patch all the environment to resolve datacenter as 'vm'
	# This change doesn't have effect after the puppet master is deployed because this branch is using an ENC
	# that is providing with this information, so this values are often discarded.
	if [ -f /etc/puppetlabs/code/environments/$f/site/facts/facts.d/lsst_facts.py ]
	then
		sed -i 's/data\[\"datacenter\"\] = fqdn\[1\]/data\[\"datacenter\"\] = \"vm\"/g' /etc/puppetlabs/code/environments/$f/site/facts/facts.d/lsst_facts.py
		grep "datacenter" /etc/puppetlabs/code/environments/$f/site/facts/facts.d/lsst_facts.py
	fi
done

if [ ! -d /opt/puppet-code ]
then
	mkdir /opt/puppet-code
fi

# If there is a shared folder for the puppet code
if [ ! -z "$(VBoxControl sharedfolder list | grep opt_puppet-code)" ]
then
	# if the sharefolder is not in the fstab yet
	if [ -z "$(grep opt_puppet-code /etc/fstab)" ]
	then
		echo "Shared puppet code dir found, mounted into: /etc/puppetlabs/code/environments/$ENVIRONMENT"
		echo "opt_puppet-code /opt/puppet-code vboxfs defaults,ro 0 0" >> /etc/fstab
		echo "/opt/puppet-code /etc/puppetlabs/code/environments/$ENVIRONMENT none defaults,ro,bind 0 0" >> /etc/fstab
		mount -a
	fi
fi

if [ ! -f /etc/puppetlabs/puppet/autosign.conf ]
then
	echo "*.us.stanford.edu" > /etc/puppetlabs/puppet/autosign.conf
	echo "*.slac.stanford.edu" >> /etc/puppetlabs/puppet/autosign.conf
fi

systemctl enable puppetserver
systemctl start puppetserver

# Registering against the puppet server and sending certificate
/opt/puppetlabs/puppet/bin/puppet agent -t

systemctl restart puppetserver


