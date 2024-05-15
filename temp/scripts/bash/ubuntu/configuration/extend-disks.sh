#!/bin/sh

# Define log file name
LOG_FILE="/logs/extend-disks-$(date '+%Y%m%d').log"

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

    echo "Extending Disk Partitions If Space Is Available"

    # Part 1: Use growpart to extend the partition - it will use the available space
    echo "Resizing partition /dev/sda3..."
    if sudo growpart /dev/sda 3; then
        echo "Partition /dev/sda3 resized successfully."
    else
        echo "Error occurred while resizing partition /dev/sda3."
        exit 1
    fi

    # Part 2: Update the system's view of disk partitions
    echo "Updating the system's view of disk partitions..."
    if sudo partprobe /dev/sda; then
        echo "System's view of disk partitions updated."
    else
        echo "Error occurred while updating disk partitions."
        exit 1
    fi

    # Part 3: Resize the LVM physical volume
    echo "Resizing the LVM physical volume on /dev/sda3..."
    if sudo pvresize /dev/sda3; then
        echo "LVM physical volume on /dev/sda3 resized."
    else
        echo "Error occurred while resizing the LVM physical volume."
        exit 1
    fi

    # Part 4-7: Handle LVM volume group and logical volume
    echo "Processing LVM volume group and logical volume..."
    VG_NAME=$(sudo pvs --noheading -o vg_name /dev/sda3 | tr -d ' ')
    echo "Volume group name obtained: $VG_NAME"
    LV_PATH=$(sudo lvdisplay -C -o lv_path --noheading $VG_NAME | tr -d ' ')
    echo "Logical volume path obtained: $LV_PATH"

    echo "Extending the logical volume to use all available space..."
    if sudo lvextend -l +100%FREE $LV_PATH; then
        echo "Logical volume extended successfully."
    else
        echo "Error occurred while extending the logical volume."
        exit 1
    fi

    echo "Resizing the filesystem on $LV_PATH..."
    if sudo resize2fs $LV_PATH; then
        echo "Filesystem resized successfully."
    else
        echo "Error occurred while resizing the filesystem."
        exit 1
    fi

    echo "Disk resize operations have completed successfully."
    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
