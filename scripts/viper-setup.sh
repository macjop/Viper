#!/bin/sh -e

VIPER_ROOT="$PWD"

# Use -sf to symlink instead of copying (default), empty otherwise.
CP_ARG="-sf"

# Make sure we're running in toplevel dir and not in i.e. scripts/
if ! test -d "etc"; then
	echo "The script should be run from Viper root directory (the one"
	echo "in which you have README and scripts/)."
	echo
	echo "Cd there, then run as: sh scripts/viper-setup.sh"
	exit 1
fi

ETH_IF=$1
if test -z "$ETH_IF"; then
	ETH_IF=sharedNetwork
fi

HOST=$2
if test -z "$HOST"; then
	HOST=viper
fi

# Install necessary packages
apt-get install slapd ldap-utils libfile-find-rule-perl libnet-ldap-perl libtext-csv-xs-perl liblist-moreutils-perl dhcp3-server-ldap make sudo libyaml-perl apache2 puppet puppetmaster libdifflcs-ruby libopenssl-ruby libshadow-ruby1.8 librrd-ruby libaugeas-ruby

# One-time viper subdirectory creation
mkdir -p /var/lib/ldap/viper
chown openldap:openldap /var/lib/ldap/viper

# Install all etc files
# FIXME: make original backup
cd "$VIPER_ROOT"
find etc -type d -exec mkdir -p /{} \;
find etc -type f -exec cp $CP_ARG "$VIPER_ROOT/{}" "/{}" \;

# Restart slapd with new configs and all.
invoke-rc.d slapd restart

# Sync Viper schema to server schema
# Not needed because the set of schemas we deliver and schema.ldif are
# already in sync.
#perl /etc/ldap/viper/scripts/schema.pl > /etc/ldap/schema/schema.ldif
#invoke-rc.d slapd restart

# Adjust local server name in dhcp.ldif:
# - Replace "viper" in ldifs/dhcp.ldif with the name of local server
# - Replace 'sharedNetwork' with name of local physical interface
# (NOTE: we don't have to do below block any more, as slapd.conf contains
# a rewrite that rewrites all searches to default host cn=viper, and ethX
# shared network has simply been replaced with another, generic string.
# So this is by default a no-op, but if a person specifies ethX and hostname
# on the command line, the replacement will be real, not no-op).
cd "$VIPER_ROOT/ldifs"
git checkout 1-dhcp.ldif || true # Load fresh copy of setup script
perl -pi -e "\$h= '$HOST'; chomp \$h; s/viper/\$h/g" 1-dhcp.ldif
perl -pi -e "s/sharedNetwork/$ETH_IF/g" 1-dhcp.ldif

# Load LDIF data into LDAP (NOTE: 'make' deletes all Viper data from LDAP
# and then loads all *ldif files, so if you want to use this approach, do not
# modify LDAP entries directly as changes will be lost -- instead, always edit
# LDIF file and run make)
make

# Restart dhcp
invoke-rc.d dhcp3-server restart

# Link preseed CGI script to web server's cgi-bin:
mkdir -p /usr/lib/cgi-bin
cp $CP_ARG "$VIPER_ROOT/scripts/preseed" /usr/lib/cgi-bin/preseed.cfg

# Copy extra parser functions to Puppet
cp $CP_ARG "$VIPER_ROOT"/etc/puppet/modules-development/custom/plugins/puppet/parser/functions/*  /usr/lib/ruby/1.8/puppet/parser/functions/

# Restart puppet server
invoke-rc.d puppetmaster restart

echo "Viper setup successful, services running."

