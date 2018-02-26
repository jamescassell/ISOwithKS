%pre
echo "################################################"
echo "#  Starting the custom install via kickstart.  #"
echo "################################################"
%end

auth --enableshadow --passalgo=sha512
cdrom
text
firstboot --disable
ignoredisk --only-use=sda
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8

network  --bootproto=dhcp --device=enp0s3 --ipv6=auto --activate
network  --hostname=localhost.localdomain

rootpw --iscrypted $6$5COcs7LbjIQ.JWf7$jY4Zz2VcQ0u60IkuB3qx7Gj0iRf1qa0DA46j6O9DEddjCtkE.nx7MEgabMFgGVcsejA3dE7OPPrrElyjSXJao/
services --enabled="chronyd"
timezone Etc/GMT --isUtc
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=sda
autopart --type=lvm
clearpart --none --initlabel

%packages
@^minimal
@core
chrony
kexec-tools

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

