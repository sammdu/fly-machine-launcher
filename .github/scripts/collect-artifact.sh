#!/bin/bash

# Identify the Machine before reading its deployed settings.
app=$(jq -er '.app' fly.json) || exit 1
machines=$(flyctl machines list --app "$app" --json) || exit 1
machine=$(jq -er 'if length == 1 then .[0].id else error("Expected exactly one Machine") end' <<< "$machines") || exit 1

state=$(jq -r '.[0].state' <<< "$machines")
devuser=$(jq -er '.[0].config.env.DEVUSER' <<< "$machines") || exit 1
workdir=$(jq -er '.[0].config.env.WORKDIR' <<< "$machines") || exit 1
user_home="/home/$devuser"

# Use the deployed filename unless the workflow supplies an override.
if [ -z "$ARTIFACT_NAME" ]; then
    ARTIFACT_NAME=$(jq -er '.[0].config.env.ARTIFACT_NAME' <<< "$machines") || exit 1
fi

# Restore the previous power state even if collection fails.
cleanup() {
    result=$?
    case "$state" in
        stopped) flyctl machine stop "$machine" --app "$app" --wait-timeout 30s || result=1 ;;
        suspended) flyctl machine suspend "$machine" --app "$app" --wait-timeout 30s || result=1 ;;
    esac
    exit "$result"
}
trap cleanup EXIT

if [ "$state" != started ]; then
    flyctl machine start "$machine" --app "$app" || exit 1
fi

flyctl machine wait "$machine" --app "$app" --state started --wait-timeout 30s || exit 1

job_status=$(flyctl ssh console --app "$app" --machine "$machine" --quiet --command "cat $user_home/.job_status") || exit 1
case "$job_status" in
    ''|*[!0-9]*)
        echo "Job is unfinished or interrupted." >&2
        exit 1
        ;;
esac
printf 'job_exit_code=%s\n' "$job_status" >> "$GITHUB_OUTPUT"

# Copy the artifacts to the runner for upload.
mkdir -p artifacts || exit 1
archive="artifacts/$ARTIFACT_NAME"
flyctl ssh sftp get --app "$app" --machine "$machine" "$user_home/$workdir/$ARTIFACT_NAME" "$archive" || exit 1
echo "archive_path=$archive" >> "$GITHUB_OUTPUT"
echo "collected=true" >> "$GITHUB_OUTPUT"
