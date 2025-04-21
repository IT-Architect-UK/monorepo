#!/bin/bash

# Script to brand an Ubuntu 24.04 server with custom company name and console text color for all users

# Default values
DEFAULT_COMPANY="Love Nodes"
DEFAULT_COLOR="Yellow"

# Color mapping to ANSI codes
declare -A COLORS
COLORS=(
    ["Red"]="31"
    ["Green"]="32"
    ["Yellow"]="33"
    ["BLUE"]="34"
    ["Magenta"]="35"
    ["Cyan"]="36"
    ["White"]="37"
    ["Bright Red"]="91"
    ["Bright Green"]="92"
    ["Bright Yellow"]="93"
    ["Bright Blue"]="94"
    ["Bright Magenta"]="95"
    ["Bright Cyan"]="96"
)

# Function to display available colors
show_colors() {
    echo "Available text colors:"
    for color in "${!COLORS[@]}"; do
        echo "  - $color"
    done
}

# Prompt with visible countdown
echo "Press any key within 5 seconds to specify custom company name and text color."
echo "Default company name: $DEFAULT_COMPANY"
echo "Default text color: $DEFAULT_COLOR"
echo -n "Starting in: "
for i in 5 4 3 2 1; do
    echo -n "$i... "
    if read -t 1 -n 1; then
        choice="custom"
        break
    fi
done
echo ""

if [ "$choice" = "custom" ]; then
    # Prompt for company name
    read -p "Enter company name (default: $DEFAULT_COMPANY): " company_name
    company_name=${company_name:-$DEFAULT_COMPANY}

    # Show available colors and prompt for color
    show_colors
    read -p "Enter text color (default: $DEFAULT_COLOR): " text_color
    text_color=${text_color:-$DEFAULT_COLOR}
else
    company_name="$DEFAULT_COMPANY"
    text_color="$DEFAULT_COLOR"
fi

# Validate color
if [ -z "${COLORS[$text_color]}" ]; then
    echo "Invalid color: $text_color. Falling back to $DEFAULT_COLOR."
    text_color="$DEFAULT_COLOR"
fi

# Get ANSI color code
color_code=${COLORS[$text_color]}

# Step 1: Set console text color for all users
echo "Setting console text color to $text_color on black for all users..."
cat << EOF | sudo tee /etc/profile.d/console-colors.sh
#!/bin/sh
echo -e "\\033[${color_code};40m"
EOF
sudo chmod +x /etc/profile.d/console-colors.sh

# Update bash prompt for all users
cat << EOF | sudo tee -a /etc/bash.bashrc
# Custom prompt with $text_color text on black background
export PS1='\\[\e[${color_code};40m\\]\\u@\\h:\\w\\\$ \\[\e[m\\]'
EOF

# Apply color settings to the current session
echo "Applying color settings to the current session..."
export PS1="\[\e[${color_code};40m\]\u@\h:\w\$ \[\e[m\]"
echo -e "\033[${color_code};40m"

# Step 2: Configure login prompt with company name and warning
# /etc/issue.net for SSH (clean, no escape codes)
echo "Configuring SSH login banner with company name: $company_name..."
cat << EOF | sudo tee /etc/issue.net
Welcome to $company_name

*****************************************************
* WARNING: Unauthorized access to this system is     *
* prohibited and may result in legal action.         *
* All activities are monitored and logged.           *
*****************************************************
EOF

# /etc/issue for console logins (includes \l for login prompt)
cat << EOF | sudo tee /etc/issue
Welcome to $company_name

*****************************************************
* WARNING: Unauthorized access to this system is     *
* prohibited and may result in legal action.         *
* All activities are monitored and logged.           *
*****************************************************

\l
EOF

# Step 3: Configure MOTD for post-login welcome with yellow text
echo "Configuring MOTD with company name: $company_name..."
cat << EOF | sudo tee /etc/update-motd.d/00-header
#!/bin/sh
printf "\\033[${color_code};40m"
printf " \\n"
printf " \\n"
printf "Welcome to %s\\n\\n" "$company_name"
printf " \\n"
EOF
sudo chmod +x /etc/update-motd.d/00-header

# Disable other MOTD scripts to prevent duplication
sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true
sudo chmod +x /etc/update-motd.d/00-header

# Step 4: Ensure SSH displays the login banner cleanly
echo "Configuring SSH to display the login banner..."
if ! grep -q "^Banner" /etc/ssh/sshd_config; then
    echo "Banner /etc/issue.net" | sudo tee -a /etc/ssh/sshd_config
else
    sudo sed -i 's|^#*Banner.*|Banner /etc/issue.net|' /etc/ssh/sshd_config
fi

# Disable MOTD banner to avoid duplication
if ! grep -q "^PrintMotd" /etc/ssh/sshd_config; then
    echo "PrintMotd no" | sudo tee -a /etc/ssh/sshd_config
else
    sudo sed -i 's|^#*PrintMotd.*|PrintMotd no|' /etc/ssh/sshd_config
fi

# Step 5: Restart SSH service (handle both ssh and sshd)
echo "Restarting SSH service..."
if systemctl is-active --quiet ssh.service; then
    sudo systemctl restart ssh.service
elif systemctl is-active --quiet sshd.service; then
    sudo systemctl restart sshd.service
else
    echo "Warning: No SSH service (ssh or sshd) found. Skipping restart."
fi

# Step 6: Notify user
echo "Branding complete!"
echo "Company name: $company_name"
echo "Text color: $text_color"
echo "Changes applied for all users and current session."
echo "Verify the new branding via console or SSH login."