has() {
    local package=$1

    if [ "$(dpkg -l | awk "/$package/ {print}" | wc -l)" -ge 1 ] || [[ $(type -t $package) == function ]] || which "$package" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

set_profile_variable() {
    local variable=$1
    local value=$2
    local targetfile=~/.profile
    local new_line="export ${variable}=${value}"
    
    # Check if the variable already exists in the file
    if grep -q "export ${variable}" "$targetfile"; then
        # If it exists, replace the existing line
        local to_replace_line_number=$(grep -n "export ${variable}" "$targetfile" | cut -d":" -f1)
        sed -i -e "${to_replace_line_number} c\\" -e "${new_line}" "$targetfile"
    else
        # If it does not exist, append the new line to the end of the file
        echo "" >> "$targetfile"
        echo "${new_line}" >> "$targetfile"
    fi

    # Source the profile to apply changes immediately
    . ~/.profile
}

windows_users() {
    local valid_users=()
    for user in $(ls -1p /mnt/c/Users | grep / | sed 's/^\(.*\)\//\1/'); do
        if [ -d "/mnt/c/Users/$user/.ssh" ]; then
            valid_users+=("$user")
        fi
    done
    echo "${valid_users[@]}"
}

path_prepend() {
    local dir="$1"

    if [[ -z "$dir" ]]; then
        echo "Uso: path_prepend <caminho>" >&2
        return 1
    fi

    # Remove barra final (exceto para "/")
    [[ "$dir" != "/" ]] && dir="${dir%/}"

    case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir${PATH:+:$PATH}" ;;
    esac
}