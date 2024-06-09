snmp.enable
snmp.set --communities public
snmp.set --syscontact "Contact Name"
snmp.set --syslocation "Company Data Centre"
snmp.get
service-control --restart vmware-vpxd
