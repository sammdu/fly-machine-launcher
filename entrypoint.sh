#!/bin/bash

# Validate the mode before changing accounts or SSH files.
case "$MODE" in
    dev|job) ;;
    *)
        echo "MODE must be dev or job" >&2
        exit 2
        ;;
esac

if [ "$MODE" = dev ] && [ -z "$SSH_AUTHORIZED_KEYS" ]; then
    echo "SSH_AUTHORIZED_KEYS must contain your public SSH key." >&2
    exit 1
fi

# Recreate the login account while reusing its persistent home.
user_home="/home/$DEVUSER"
if ! getent passwd "$DEVUSER" > /dev/null; then
    useradd --home-dir "$user_home" --shell /bin/bash "$DEVUSER" || exit 1
fi

# Unlock the account for SSH keys; sshd_config disables password login.
passwd -d "$DEVUSER" || exit 1
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$DEVUSER" > "/etc/sudoers.d/$DEVUSER" || exit 1
chmod 0440 "/etc/sudoers.d/$DEVUSER" || exit 1

install -d -o "$DEVUSER" -g "$DEVUSER" "$user_home" || exit 1

if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    install -d -o root -g root -m 0755 /run/sshd || exit 1
    install -d -o "$DEVUSER" -g "$DEVUSER" -m 0700 "$user_home/.ssh" || exit 1
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > "$user_home/.ssh/authorized_keys" || exit 1
    chown "$DEVUSER:$DEVUSER" "$user_home/.ssh/authorized_keys" || exit 1
    chmod 0600 "$user_home/.ssh/authorized_keys" || exit 1

    # Preserve the server's SSH identity across restarts.
    host_key="$user_home/.ssh/ssh_host_ed25519_key"
    if [ ! -f "$host_key" ]; then
        ssh-keygen -q -t ed25519 -N "" -f "$host_key" || exit 1
    fi
    ssh_options=(-o "HostKey=$host_key" -o "AllowUsers=$DEVUSER")
    /usr/sbin/sshd -t "${ssh_options[@]}" || exit 1
    /usr/sbin/sshd -D -e "${ssh_options[@]}" &
    ssh_pid=$!
fi

cd "$user_home" || exit 1

# The home volume survives restarts and is replaced on deploy.
status_file="$user_home/.job_status"
if [ ! -f "$status_file" ]; then
    echo running > "$status_file" || exit 1
    runuser -u "$DEVUSER" -- "$@"
    status=$?
    echo "$status" > "$status_file" || exit 1
    echo "Job exited with status $status."
    if [ "$MODE" = job ]; then
        exit "$status"
    fi
else
    echo "Job was already attempted; leaving the Machine idle."
fi

if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    wait "$ssh_pid"
    exit "$?"
fi

exec sleep infinity
