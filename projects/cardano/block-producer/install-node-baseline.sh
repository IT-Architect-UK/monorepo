#!/bin/bash

# Get the currently logged-in user
current_user=$(whoami)
echo "Current user: $current_user"
export current_user

echo "Disabling Non-Root Users Excluding the Logged on User"
# Get the username of the user executing the script (even if using sudo)
logged_in_user=$(who am i | awk '{print $1}')
# Disable all non-root users except the user executing the script
getent passwd | while IFS=: read -r username _ uid _; do
    if [ "$uid" -ge 1000 ] && [ "$username" != "root" ] && [ "$username" != "nobody" ] && [ "$username" != "$logged_in_user" ]; then
        sudo passwd -l "$username"
        echo "User $username has been disabled."
    fi
done


