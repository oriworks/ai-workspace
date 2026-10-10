#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/../utils/functions.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    widows_user_variable=WINDOWS_USER
    list_windows_users=($(windows_users))

    if [ ${#list_windows_users[@]} -eq 0 ]; then
        echo "Error: No valid windows user found!"
    elif [ ${#list_windows_users[@]} -eq 1 ]; then
        set_profile_variable $widows_user_variable ${list_windows_users[0]}
    else
        echo "Multiple valid Windows users found with .ssh directories:"
        for i in "${!list_windows_users[@]}"; do
            echo "$((i+1)). ${list_windows_users[i]}"
        done
        read -p "Please select the number corresponding to the desired WINDOWS_USER: " user_choice
        if [[ "$user_choice" -ge 1 && "$user_choice" -le ${#list_windows_users[@]} ]]; then
            set_profile_variable "$widows_user_variable" "${list_windows_users[$((user_choice-1))]}"
        else
            echo "Invalid selection. Please run the script again and select a valid number."
        fi
    fi
else
    echo "Warning: This script should be sourced, not executed directly."
    exit 1;
fi
