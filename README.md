# Fly Machine Github Actions Template

Deploy one Linux machine on Fly.io through GitHub Actions. Both modes run [job.sh](job.sh). SSH is configured when `SSH_AUTHORIZED_KEYS` is set:

| Mode | After `job.sh` exits |
| --- | --- |
| Stay accessible via SSH | Keep SSH running, including if provisioning failed. |
| Execute job.sh and shutdown | Stop the Machine; optionally collect its artifacts. |

Each deployment replaces the Machine and volume, deleting previous files, and runs `job.sh` once. Ordinary starts retain the files and stay idle.

## Setup

1. Review [fly.json](fly.json):
   - Set the app name and review the configured region.
   - Adjust resources: defaults are 4 shared CPUs, 4 GB RAM, and a 15 GB persistent volume.
   - Set `$DEVUSER` to choose the username; default `dev`.
   - Set `$WORKDIR` for work and artifacts, relative to the user's home; default `Documents`.
   - Set `$ARTIFACT_NAME` for the artifact file name; default `output.tar.gz`.
2. Review [Dockerfile](Dockerfile), which defaults to `ubuntu:latest`, the latest Ubuntu LTS image.
3. Put tool installation, provisioning, and workload commands in [job.sh](job.sh).
4. Add the repository secret `FLY_API_TOKEN`: use an organization token to create the app, or an app deploy token for an existing app. Set the repository variable `FLY_ORG` for organizations other than `personal`.
5. For SSH access (required in dev mode, optional in job mode), use an existing key or generate one locally:

   ```sh
   mkdir -p ~/.ssh
   ssh-keygen -t ed25519 -a 100 -f ~/.ssh/fly-machine -C fly-machine
   cat ~/.ssh/fly-machine.pub
   ```

   Add the public key to the repository secret `SSH_AUTHORIZED_KEYS`. Keep the private key on your computer.
6. Run [Deploy Machine](../../actions/workflows/fly-deploy.yml) and choose a mode.

The workflow creates the app, volume, and dedicated public IPv4 address as needed.

## SSH access

The run summary provides the connection command, key fingerprints, and dashboard link for runtime logs. SSH starts before `job.sh`. Connect with your SSH client or [VS Code Remote-SSH](https://code.visualstudio.com/docs/remote/ssh).

Set `$DEVUSER` locally to the username configured in `fly.json`.

```sh
ssh -i ~/.ssh/fly-machine "$DEVUSER@YOUR_APP_NAME.fly.dev"
cd ~/Documents
```

If using an existing key, replace `~/.ssh/fly-machine` with its private-key path. The configured user has passwordless `sudo`.

Forward local port `8080` to the Machine's port `8080`:

```sh
ssh -i ~/.ssh/fly-machine -N -L 127.0.0.1:8080:127.0.0.1:8080 "$DEVUSER@YOUR_APP_NAME.fly.dev"
```

`-L` takes `<local_ip>:<local_port>:<remote_ip>:<remote_port>`. Open `http://127.0.0.1:8080` and keep SSH connected.

In VS Code Remote-SSH, use the **Ports** view.

## Collecting job artifacts

`job.sh` runs as `$DEVUSER`. The sample works in `$HOME/$WORKDIR` and packages `result.txt` as `$ARTIFACT_NAME`. Return a nonzero exit code on failure.

| Input | Purpose |
| --- | --- |
| `artifact_name` | Artifact file name in `$WORKDIR`; blank uses the deployed `$ARTIFACT_NAME`. |
| `retention_days` | GitHub artifact retention; default `7` days, within your repository's limit. |
| `timeout_minutes` | End-to-end time limit per run, including deployment, waiting, and artifact transfer; default `180` minutes (`<= 360`). |

Deployment attempts collection only in **Execute job.sh and shutdown** mode with a positive timeout.

A workflow timeout leaves the Machine's job running; it finishes and shuts down on its own. Run [Collect artifact](../../actions/workflows/fly-collect-artifact.yml) after the job finishes if deployment did not collect its artifact.

Collection starts the Machine if needed, downloads the completed job's artifacts, and restores its previous power state.

Uploaded artifacts retain their filenames and formats. Download them from the run summary or **Artifacts** section. A recorded nonzero job exit code fails the run after upload.

## Storage

The volume persists `/home`, including `~/Documents`, `~/.ssh`, and job status. Files outside `/home` are ephemeral.

