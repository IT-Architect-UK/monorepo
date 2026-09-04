# shellcheck shell=sh
# NOT a shell script: these are commands for the vCenter appliance shell
# (appliancesh). Paste them into an SSH session on the VCSA one at a time.
snmp.enable
snmp.set --communities public
snmp.set --syscontact "Contact Name"
snmp.set --syslocation "Company Data Centre"
snmp.get
service-control --restart vmware-vpxd
