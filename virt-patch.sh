#!/bin/bash

# Creator: crypt0jan
# Github: https://github.com/crypt0jan/virt-patch.git
#
# To fetch new or modified dirs/files, usage:
#   ./virt-patch.sh bustakube-OLD.qcow2 bustakube-NEW.qcow2
# To only list new or modified dirs/files, usage:
#   ./virt-patch.sh --list bustakube-OLD.qcow2 bustakube-NEW.qcow2
# To patch an unpatched disk image:
#   ./virt-patch.sh --patch bustakube-OLD.qcow2
#
# TODO:
# - progress indicator whilst waiting for a job to complete

#############
# Variables #
#############

CSV="$PWD/diff.csv"
MODIFIED="$PWD/modified"
MOUNT="$PWD/mymountpoint"
LIST=false
PATCH=false
FETCH=false
OLDFILE=
NEWFILE=

#############
# Functions #
#############

# Function to display the script's usage
usage () {
    echo -e "This script requires a flag and at least one additional argument.  Examples:"
    echo -e "- Fetch changes: ./virt-patch.sh --fetch bustakube-OLD.qcow2 bustakube-NEW.qcow2"
    echo -e "- List changes: ./virt-patch.sh --list bustakube-OLD.qcow2 bustakube-NEW.qcow2"
    echo -e "- Patch image: ./virt-patch.sh --patch bustakube-OLD.qcow2"
}

# Function to check if requisites are installed.
check_req () {

    echo -n "Checking if requisites are installed..."
    sleep 1

    type virt-diff >/dev/null 2>&1 || { echo >&2 "I require virt-diff but it's not installed.  Aborting."; exit 1; }
    type guestmount >/dev/null 2>&1 || { echo >&2 "I require guestmount but it's not installed.  Aborting."; exit 1; }
    type rsync >/dev/null 2>&1 || { echo >&2 "I require rsync but it's not installed.  Aborting."; exit 1; }

    echo -e "[ PASS ]"

}

# Function to check if a csv exists
check_csv () {
    if [[ -f "$1" ]]; then
	return 0
    else
	return 1
    fi
}

# Function to create an empty csv file.
create_csv () {
    touch $1
    if [ $? -ne 0 ]; then
        echo -e "\tSomething went wrong while creating '$1'.  Check if we have permission to create files."
        exit 1
    else
        return 0
    fi
}

# Function to check for changes between disk images. It will list the changes in '$CSV'.
create_diff () {

    virt-diff -a $OLDFILE -A $NEWFILE --csv > $CSV
    if [ $? -ne 0 ]; then
        echo -e "\tOh oh!  Something went wrong while running virt-diff or updating '$CSV'.  Please investigate."
        exit 1
    else
        return 0
    fi

}

# Function to create a directory
create_dir () {

    if [ -d "$1" ]; then
        echo -e "\t$1 already exists."
        sleep 1

        read -p $'\tShall I remove it and recreate it (y/Y) or do you want to preserve its contents (n/N)?' choice
        case "$choice" in 
          y|Y ) 
            echo -e "\tOkay!  I will recreate the directory."
    	    sleep 1

	    rm -rf $1
	    if [ $? -eq 0 ]; then
	        mkdir $1
	        if [ $? -eq 0 ]; then
                    return 0
                else
                    echo -e "\tUnable to create directory '$1'.  Exiting."
                    exit 1
                fi
	    else
	        echo -e "\tUnable to remove directory '$1'.  Exiting."
	        exit 1
	    fi
	    ;;
          n|N ) echo -e "Okay.  Exiting." && exit 1;;
          * ) echo -e "\tInvalid option.";;
        esac
    else
        echo -e "\tCreating directory '$1'..."
        sleep 1

        mkdir $1
        if [ $? -eq 0 ]; then
            return 0
	else
	    echo -e "\tUnable to create directory '$1'.  Exiting."
	    exit 1
	fi
    fi

}

# Function to guestmount a disk image
guest_mount () {

    guestmount -a $1 -m /dev/sda1 $2 $MOUNT
    if [ $? -ne 0 ]; then
        echo -e "I was unable to mount '$1' in '$MOUNT'."
        sleep 1

        echo -e "Please tell me on what device '$MOUNT' is located (i.e. /dev/sda1):"
        read device

        echo -e "Let's try the mount again with your input: '$device'..."
        sleep 1

        guestmount -a $1 -m $device $2 $MOUNT
        if [ $? -eq 0 ]; then
            echo -e "I think it worked.  Let's check if we can find the mount point..."
            sleep 1

            if mount | grep $MOUNT > /dev/null; then
            	echo -e "Mount point found!"
            	sleep 1
                return 0
            else
                echo -e "'$MOUNT' was not mounted.  Exiting."
                exit 1
            fi
        fi
    else
        return 0
    fi

}

# Function to fetch directories and files from a new(er) disk image
fetch () {

    # Create folder '$MODIFIED' if it does not exist
    echo -e "Checking if directory '$MODIFIED' exists."
    if create_dir "$MODIFIED"; then
	echo -e "\tDirectory '$MODIFIED' successfully created.  You may proceed."
        sleep 1
    fi

    # Create folder '$MOUNT' if it does not exist
    echo -e "Checking if directory '$MOUNT' exists."
    if create_dir "$MOUNT"; then
	echo -e "\tDirectory '$MOUNT' successfully created.  You may proceed."
        sleep 1
    fi

    # Checking if $MOUNT is mounted
    if mount | grep $MOUNT > /dev/null; then
        echo -e "'$MOUNT' is already mounted!"
        sleep 1

        read -p "Continue with the already mounted device (y/n)?" choice
        case "$choice" in 
          y|Y ) echo -e "Okay!  You may proceed.";;
          n|N ) echo -e "Okay.  Exiting." && exit 1;;
          * ) echo -e "Invalid option.";;
        esac
    fi

    # Guestmount the new(er) disk image in $MOUNT
    echo -e "Going to mount the new(er) disk image in '$MOUNT'..."
    sleep 1

    if guest_mount "$1" "--ro"; then
	echo -e "\t'$MOUNT' successfully mounted!  You may proceed."
        sleep 1
    fi

    # Loop through the csv and copy over directories and files to folder '$MODIFIED'
    # Example CSV: '=,-,0644,14,/mynewdirectory/FLAG.txt'
    echo -e "Looping through CSV and creating necessary directories and files within '$MODIFIED'"
    sleep 1

    OLDIFS=$IFS
    IFS=,
    [ ! -f $CSV ] && { echo "'$CSV' file not found"; exit 99; }
    while read status type perms size path
    do
        if [ $status != "#" ]; then
	    echo -e "-- Found: '$path'"
	    sleep 1

	    if [ $type == "d" ]; then
	        if [ $status != "-" ]; then
	            mkdir -p $MODIFIED$path
	            if [ $? -eq 0 ]; then
	            	echo -e "\t[ CREATED ] Directory: '$MODIFIED$path'"
	            	sleep 1
	            else
	            	echo -e "\tFailed to create directory '$MODIFIED$path'"
	            	sleep 1
	            fi
	        else
		    echo -e "\t[ SKIPPING ] This script doesn't handle deletions.  Remove '$path' manually if necessary."
		fi
	    else
		if [ $status != "-" ]; then
	            DIR=$( dirname "$path" )
	            mkdir -p $MODIFIED$DIR
	            if [ $? -eq 0 ]; then
	                cp $MOUNT$path $MODIFIED$path
	                if [ $? -eq 0 ]; then
	            	    echo -e "\t[ COPIED ] File $MODIFIED$path"
	            	    sleep 1
	                fi
	            fi
		else
		    echo -e "\t[ SKIPPING ] This script doesn't handle deletions.  Remove '$path' manually if necessary."
		fi
	    fi
	fi
    done < $CSV
	IFS=$OLDIFS

	# Unmount
	echo -e "Okay. Next up: unmounting!"
	sleep 1

	guestunmount $MOUNT
	if [ $? -eq 0 ]; then
	    echo -e "\tUnmount was successful!"
	    sleep 1

	    # Remove the $MOUNT directory
	    echo -e "Removing mount directory.."
	    sleep 1

	    rmdir $MOUNT
	    if [ $? -ne 0 ]; then
	    	echo -e "\tFailed to remove the mount directory.  Please remove it manually."
	    	sleep 1
	    fi
	else
	    echo -e "\tUnmount failed. Please unmount it yourself using: 'guestunmount $MOUNT'"
	    sleep 1
	fi

	# Aaaaaand, we're done!
	return 0

}

# Function to patch an old/unpatched disk image.
patch_image () {

    # Create folder '$MOUNT' if it does not exist
    echo -e "Checking if directory '$MOUNT' exists."
    if create_dir "$MOUNT"; then
	echo -e "\tDirectory '$MOUNT' successfully created.  You may proceed."
        sleep 1
    fi

    # Check if anything is mounted there
    if mount | grep $MOUNT > /dev/null; then
        echo -e "'$MOUNT' is already mounted!"
        sleep 1

        read -p "Continue with the already mounted device (y/n)?" choice
        case "$choice" in 
          y|Y ) echo -e "Okay!  You may proceed.";;
          n|N ) echo -e "Okay.  Exiting." && exit 1;;
          * ) echo -e "Invalid option.";;
        esac
    fi

    # Guestmount the old, unpatched disk image in '$MOUNT'
    echo -e "Going to mount the old, unpatched disk image in '$MOUNT'..."
    sleep 1

    if guest_mount "$1"; then
	echo -e "\t'$MOUNT' successfully mounted!  You may proceed."
        sleep 1
    fi

    # Recursively copy over files that are present in '$MODIFIED'
    echo -e "Copying over some files..."
    sleep 1

    rsync -uav $MODIFIED/ $MOUNT/ >/dev/null 2>&1
    if [ $? -eq 0 ]; then
	echo -e "\tRsync completed!"
	sleep 1
    else
	echo -e "\tSomething went wrong while rsyncing '$MODIFIED/' to '$MOUNT/'"
	sleep 1
    fi

    # Unmount
    echo -e "Okay. Next up: unmounting!"
    sleep 1

    guestunmount $MOUNT
    if [ $? -eq 0 ]; then
        echo -e "\tUnmount was successful!"
        sleep 1

        # Remove the $MOUNT directory
        echo -e "Removing mount directory.."
        sleep 1

        rmdir $MOUNT
        if [ $? -ne 0 ]; then
            echo -e "\tFailed to remove the mount directory.  Please remove it manually."
	    sleep 1
	fi

	echo -e "\tDone!"
    else
        echo -e "\tUnmount failed. Please unmount it yourself using: 'guestunmount $MOUNT'"
    fi

}

#############
# ASCII ART #
#############

cat << "EOF"
 __      _______ _____ _______     _____     _______ _____ _    _
 \ \    / |_   _|  __ |__   __|   |  __ \ /\|__   __/ ____| |  | |
  \ \  / /  | | | |__) | | |______| |__) /  \  | | | |    | |__| |
   \ \/ /   | | |  _  /  | |______|  ___/ /\ \ | | | |    |  __  |
    \  /   _| |_| | \ \  | |      | |  / ____ \| | | |____| |  | |
     \/   |_____|_|  \_\ |_|      |_| /_/    \_|_|  \_____|_|  |_|
                                                                  
EOF

##################
# GENERAL CHECKS #
##################

# Check for flags
while [ $# -ne 0 ]
do
    case "$1" in
	--fetch | -f)
		if [ $# -ne 3 ]; then
			echo -e "This flag requires three arguments, being '--fetch' (1), an old disk image (2), and a new disk image (3)."
			exit 1
		fi
		shift
		LIST=false
		PATCH=false
		FETCH=true
		OLDFILE="$1"
		NEWFILE="$2"
		;;
	--list | -l)
		if [ $# -ne 3 ]; then
			echo -e "This flag requires three arguments, being '--list' (1), an old disk image (2), and a new disk image (3)."
			exit 1
		fi
		shift
		LIST=true
		PATCH=false
		FETCH=false
		OLDFILE="$1"
		NEWFILE="$2"
		;;
	--patch | -p)
		if [ $# -ne 2 ]; then
			echo -e "This flag requires two arguments, being '--patch' (1), and an old disk image (2)."
			exit 1
		fi
		shift
       		LIST=false
		PATCH=true
		FETCH=false
		OLDFILE="$1"
		;;
    esac
    shift
done

##########################
# Let's get things done! #
##########################

# If the --list flag is used, do this:
if [ "$LIST" == true ]; then
    echo -e " "
    echo -e "[ LIST MODE ]"
    echo -e " "
    sleep 1

    check_req

    echo -n "Checking if the other two arguments are actually files: "
    sleep 1

    # Check if both files are actually files, or exit.
    if [[ ! -f "$OLDFILE" ]]; then
        echo -e "\t'$OLDFILE' is not a file!  Exiting."
        exit 1
    fi

    if [[ ! -f "$NEWFILE" ]]; then
        echo -e "\t'$NEWFILE' is not a file!  Exiting."
	exit 1
    fi

    echo -e "[ PASS ]"
    sleep 1

    echo -e "Checking for an existing csv file: "
    sleep 1

    # Check if a csv file exists.
    if check_csv "$CSV"; then
        echo -e "\tFile exists."
	read -p $'\tOverwrite it (o/O), or quit (q/Q)?' choice
        case "$choice" in 
          q|Q )
		echo -e "Okay.  Bye bye!"
		exit 0
		;;
          o|O )
		echo -e "\tYou chose to overwrite the existing file."
		;;
          * )
		echo -e "\tInvalid option.  Choose overwrite (o/O) or quit (q/Q)."
		;;
        esac
    else
	echo -e "\tNo csv file found. Creating..."
	sleep 1

	if create_csv "$CSV"; then
            echo -e "\tEmpty csv successfully created."
            sleep 1
	fi
    fi

    echo -e "Running virt-diff to update the csv with new and/or modified directories and files."
    sleep 1

    if create_diff "$OLDFILE" "$NEWFILE"; then
	echo -e "\tCSV updated."
	sleep 1
	echo -e "\tOpen '$CSV' to view the changes."
    fi

# If the --patch flag is used, do this:
elif [ "$PATCH" == true ]; then
    echo -e " "
    echo -e "[ PATCH MODE ]"
    echo -e " "
    sleep 1

    check_req

    # If it exists, check if there are any files or directories in it. If not, exit.
    echo -n "Checking if directory '$MODIFIED' is present: "
    sleep 1

    if [ -d "$MODIFIED" ]; then
    	echo -e "[ PASS ]"
	echo -e "Let's check if it is empty or not..."
	sleep 1

	if [ ! "$(ls -A $MODIFIED)" ]; then
	    echo -e "'$MODIFIED' is empty.  Nothing to patch.  Bye!"
	    exit 1
	else
	    echo -e "\t'$MODIFIED' is not empty.  Let's patch!"
	    sleep 1

            if patch_image "$OLDFILE"; then
		echo -e "Successfully patched your disk image.  Bye bye!"
		exit 0
	    else
		echo -e "Something went wrong while patching your disk image.  Please investigate."
		exit 1
	    fi
	fi
    else
	echo -e "There's nothing to patch.  Be sure to have directory '$MODIFIED' present."
    fi

# If the --fetch or -f flag is used, do this:
elif [ "$FETCH" == true ]; then
    echo -e " "
    echo -e "[ FETCH MODE ]"
    echo -e " "
    sleep 1

    check_req

    echo -n "Let's check if you gave me at least two files to work with: "
    sleep 1

    # Check if both files are actually files, or exit.
    if [[ ! -f "$OLDFILE" ]]; then
	echo -e "[ FAIL ]"
        echo -e "\t'$OLDFILE' is not a file!  Exiting."
        exit 1
    fi

    if [[ ! -f "$NEWFILE" ]]; then
	echo -e "[ FAIL ]"
        echo -e "\t'$NEWFILE' is not a file!  Exiting."
        exit 1
    fi

    echo -e "[ PASS ]"
    sleep 1

    echo -e "Let's check for an existing csv file..."
    sleep 1

    if check_csv "$CSV"; then
        echo -e "\tFile exists."
        read -p $'\tOverwrite it (o/O), continue using the existing csv (c/C), or quit (q/Q)?' choice
        case "$choice" in 
	    c|C )
		echo -e "\tOkay.  Using the existing csv file."
		sleep 1
		;;
	    q|Q )
		echo -e "Okay.  Bye bye!"
		exit 0
		;;
	    o|O )
		echo -e "\tYou chose to overwrite the existing file."
		sleep 1

		echo -e "Running virt-diff to update the csv with new and/or modified directories and files."
    		sleep 1

		if create_diff "$OLDFILE" "$NEWFILE"; then
	            echo -e "\tCSV updated."
		    sleep 1
		    echo -e "\tOpen '$CSV' to view the changes."
		fi
		;;
	    * )
		echo -e "\tInvalid option.  Choose overwrite (o/O) or quit (q/Q)."
		;;
	esac

    else
	echo -e "\tFile not found."
	echo -e "Creating '$CSV'..."
	sleep 1

	if create_csv "$CSV"; then
            echo -e "\tEmpty csv successfully created."
            sleep 1
	fi

        echo -e "Running virt-diff to update the csv with new and/or modified directories and files."
        sleep 1

	if create_diff "$OLDFILE" "$NEWFILE"; then
	    echo -e "\tCSV updated."
	    sleep 1
	    echo -e "\tOpen '$CSV' to view the changes."
	fi
    fi

	# Fetch all changes
	if fetch "$NEWFILE"; then
            echo -e "Successfully fetched the changes and put them in folder '$MODIFIED'.  Bye bye!"
	    sleep 1
	    exit 0
	else
	    echo -e "Something went wrong while fetching the changes.  Please investigate."
	    sleep 1
	    exit 1
	fi

else
    usage
fi # End of getting things done.
