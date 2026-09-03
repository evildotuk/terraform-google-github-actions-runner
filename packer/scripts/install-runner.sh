#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

retry() {
  local attempts=0
  local max_attempts=5

  until "$@"; do
    attempts=$((attempts + 1))
    if (( attempts >= max_attempts )); then
      echo "Command failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    sleep $((attempts * 5))
  done
}

sudo_apt_get() {
  sudo env DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

if [[ -z "${RUNNER_VERSION:-}" || -z "${RUNNER_SHA256:-}" || -z "${TRIVY_VERSION:-}" || -z "${TRIVY_SHA256:-}" ]]; then
  echo "RUNNER_VERSION, RUNNER_SHA256, TRIVY_VERSION, and TRIVY_SHA256 are required" >&2
  exit 1
fi

retry sudo_apt_get update
retry sudo_apt_get install -y ca-certificates curl git gnupg jq cron

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl --fail --silent --show-error --location --retry 5 \
  https://download.docker.com/linux/ubuntu/gpg \
  --output /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

architecture="$(dpkg --print-architecture)"
ubuntu_codename="$(awk -F= '$1 == "VERSION_CODENAME" { gsub(/\"/, "", $2); print $2 }' /etc/os-release)"

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${ubuntu_codename}
Components: stable
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

curl --fail --silent --show-error --location --retry 5 \
  https://packages.cloud.google.com/apt/doc/apt-key.gpg |
  sudo gpg --dearmor --yes --output /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
  sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

retry sudo_apt_get update

required_packages=(
  containerd.io
  docker-buildx-plugin
  docker-ce
  docker-ce-cli
  docker-compose-plugin
  google-cloud-cli
  google-cloud-cli-gke-gcloud-auth-plugin
  kubectl
)

for package in "${required_packages[@]}"; do
  if ! apt-cache show "$package" >/dev/null 2>&1; then
    echo "Required package is unavailable: $package" >&2
    apt-cache search "${package#google-cloud-cli-}" >&2 || true
    exit 1
  fi
done

retry sudo_apt_get install -y "${required_packages[@]}"

ops_agent_installer=/tmp/add-google-cloud-ops-agent-repo.sh
retry curl --fail --silent --show-error --location \
  https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh \
  --output "$ops_agent_installer"
sudo env DEBIAN_FRONTEND=noninteractive bash "$ops_agent_installer" --also-install

if ! id -u actions-runner >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash actions-runner
fi
sudo usermod -aG docker actions-runner

runner_archive="/tmp/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
retry curl --fail --silent --show-error --location \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
  --output "$runner_archive"
echo "${RUNNER_SHA256}  ${runner_archive}" | sha256sum --check --strict

trivy_archive="/tmp/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
trivy_extract_dir="$(mktemp -d)"
retry curl --fail --silent --show-error --location \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
  --output "$trivy_archive"
echo "${TRIVY_SHA256}  ${trivy_archive}" | sha256sum --check --strict
tar --extract --gzip --file "$trivy_archive" --directory "$trivy_extract_dir" trivy
sudo install -o root -g root -m 0755 "$trivy_extract_dir/trivy" /usr/local/bin/trivy

sudo install -d -o actions-runner -g actions-runner /runner /runner-tmp
sudo install -d -o actions-runner -g actions-runner -m 0750 /home/actions-runner/.cache/trivy
sudo tar --extract --gzip --file "$runner_archive" --directory /runner
sudo env DEBIAN_FRONTEND=noninteractive /runner/bin/installdependencies.sh
sudo chown -R actions-runner:actions-runner /runner /runner-tmp
sudo -u actions-runner env HOME=/home/actions-runner sh -c 'cd "$HOME" && exec /usr/local/bin/trivy --version'
sudo systemctl enable docker cron

sudo rm -f "$runner_archive" "$trivy_archive"
sudo_apt_get clean
sudo rm -rf /var/lib/apt/lists/* /tmp/*
