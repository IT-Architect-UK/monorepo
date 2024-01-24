#!/bin/bash

# Define the scripts directory
SCRIPTS_DIR="/source-files/github/Monorepo/Scripts/Bash/Ubuntu"

# Define log file name
LOG_FILE="/logs/server-baseline-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)"

    # Verify sudo privileges without password
    if ! sudo -n true 2>/dev/null; then
        echo "Error: User does not have sudo privileges or requires a password for sudo."
        exit 1
    fi

    # List of scripts to run
    SCRIPTS_TO_RUN=(
        "Packages/install-webmin.sh"
        "Configuration/extend-disks.sh"
        "Configuration/disable-ipv6.sh"
        "Configuration/dns-default-gateway.sh"
        "Configuration/setup-iptables.sh"
        "Configuration/disable-cloud-init.sh"
        "Configuration/apt-get-upgrade.sh"
    )

    for script in "${SCRIPTS_TO_RUN[@]}"; do
        script_path="${SCRIPTS_DIR}/${script}"

        # Check if the script exists
        if [ -f "$script_path" ]; then
            echo "Processing $script_path"

            # Change permission
            echo "Changing permission for $script_path"
            sudo chmod +x "$script_path"

            # Execute the script
            echo "Executing $script_path"
            if sudo "$script_path"; then
                echo "$script executed successfully."
            else
                echo "Error occurred while executing $script."
                exit 1
            fi
        else
            echo "Script $script_path does not exist."
        fi
    done

    echo "All specified scripts have been executed."
    echo "Script completed successfully on $(date). Now Rebooting..."
} 2>&1 | tee -a $LOG_FILE
    reboot
