FROM ubuntu:latest

RUN apt-get update && apt-get install -y --no-install-recommends bash ca-certificates fdisk htop iproute2 nano nftables openssh-server sudo util-linux && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh job.sh /usr/local/bin/
COPY sshd_config /etc/ssh/sshd_config

ENTRYPOINT ["/bin/bash", "/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash", "/usr/local/bin/job.sh"]
