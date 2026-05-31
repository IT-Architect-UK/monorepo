# Enable SNMP service
esxcli system snmp set --enable true

# Set SNMP community string
esxcli system snmp set --communities public

# Optional: Set SNMP target
esxcli system snmp set --targets 192.168.123.123@161/public

# Start SNMP service
/etc/init.d/snmpd start

# Verify SNMP configuration
esxcli system snmp get
