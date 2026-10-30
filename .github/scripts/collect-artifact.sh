#!/bin/bash

# Identify the Machine before reading its deployed settings.
app=$(jq -er '.app' fly.json) || exit 1
machines=$(flyctl machines list --app "$app" --json) || exit 1
machine=$(jq -er 'if length == 1 then .[0].id else error("Expected exactly one Machine") end' <<< "$machines") || exit 1

state=$(jq -r '.[0].state' <<< "$machines")
mode=$(jq -r '.[0].config.env.MODE' <<< "$machines")
devuser=$(jq -er '.[0].config.env.DEVUSER' <<< "$machines") || exit 1
workdir=$(jq -er '.[0].config.env.WORKDIR' <<< "$machines") || exit 1
user_home="/home/$devuser"

# Use the deployed filename unless the workflow supplies an override.
if [ -z "$ARTIFACT_NAME" ]; then
    ARTIFACT_NAME=$(jq -er '.[0].config.env.ARTIFACT_NAME' <<< "$machines") || exit 1
fi

if [ "$mode" = job ] && [ "$state" != stopped ]; then
    echo "Job is still running. Collect its archive after it stops." >&2
    exit 1
fi

# Restore the startup command and stopped state after recovery, including on failure.
cleanup() {
    result=$?
    flyctl machine update "$machine" --app "$app" --machine-config "$restore_config" --skip-start --yes || result=1
    exit "$result"
}

if [ "$state" = stopped ]; then
    # Null restores the image's default command after a temporary exec override.
    restore_config=$(jq -c '{init: {exec: .[0].config.init.exec}}' <<< "$machines") || exit 1
    trap cleanup EXIT
    flyctl machine update "$machine" --app "$app" --machine-config '{"init":{"exec":["/bin/sleep","infinity"]}}' --skip-health-checks --yes || exit 1
fi

flyctl machine wait "$machine" --app "$app" --state started --wait-timeout 2m || exit 1

# Copy the archive to the runner for upload.
mkdir -p artifacts || exit 1
archive="artifacts/$ARTIFACT_NAME"
flyctl ssh sftp get --app "$app" --machine "$machine" "$user_home/$workdir/$ARTIFACT_NAME" "$archive" || exit 1
echo "archive_path=$archive" >> "$GITHUB_OUTPUT"
echo "collected=true" >> "$GITHUB_OUTPUT"

status_command="cat $user_home/.job-exit-code"

if job_status=$(flyctl ssh console --app "$app" --machine "$machine" --quiet --command "$status_command"); then
    # Only numeric exit codes describe a completed job.
    case "$job_status" in
        ''|*[!0-9]*) ;;
        *) printf 'job_exit_code=%s\n' "$job_status" >> "$GITHUB_OUTPUT" ;;
    esac
fi
