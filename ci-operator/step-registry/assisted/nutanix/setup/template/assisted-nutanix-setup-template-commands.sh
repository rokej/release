#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

echo "************ nutanix assisted test-infra setup template command ************"

# ensure LEASED_RESOURCE is set
if [[ -z "${LEASED_RESOURCE}" ]]; then
  echo "Failed to acquire lease"
  exit 1
fi

# shellcheck source=/dev/random
source $SHARED_DIR/nutanix_context.sh

echo "$(date -u --rfc-3339=seconds) - Getting PE Name"

pc_url="https://${PE_HOST}:${PE_PORT}"
clusters_api_ep="${pc_url}/api/nutanix/v3/clusters/list"
un="${NUTANIX_USERNAME}"
pw="${NUTANIX_PASSWORD}"
data="{
  \"kind\": \"cluster\"
}"

clusters_json=$(curl -ks -u "${un}":"${pw}" -X POST ${clusters_api_ep} -H "Content-Type: application/json" -d @-<<<"${data}")
pe_name=$(echo "${clusters_json}" | jq -r '.entities[] | select (.spec.name != "Unnamed") | .spec.name' | head -n 1)

if [[ -z "${pe_name}" ]]; then
    echo "$(date -u --rfc-3339=seconds) - Cannot get PE Name"
    exit 1
fi

subnets_api_ep="${pc_url}/api/nutanix/v3/subnets/list"
data="{
  \"kind\": \"subnet\"
}"
subnets_json=$(curl -ks -u "${un}":"${pw}" -X POST ${subnets_api_ep} -H "Content-Type: application/json" -d @-<<<"${data}")
subnet_name=$(echo "${subnets_json}" | jq -r ".entities[] | .spec.name"  | head -n 1)

echo "$(date -u --rfc-3339=seconds) - PE Name: ${pe_name}"
echo "$(date -u --rfc-3339=seconds) - Subnet Name: ${subnet_name}"

export NUTANIX_ENDPOINT="${NUTANIX_HOST}"
export NUTANIX_CLUSTER_NAME="${pe_name}"
export NUTANIX_SUBNET_NAME="${subnet_name}"

mkdir -p build/packer
cp -r packer_files/nutanix_centos_template/* build/packer/
cd build/packer/

# Create packer variables file
cat >> nutanix-params.hcl << EOF
nutanix_username = "${NUTANIX_USERNAME}"
nutanix_password = "${NUTANIX_PASSWORD}"
nutanix_endpoint = "${NUTANIX_ENDPOINT}"
nutanix_port = "${NUTANIX_PORT}"
nutanix_cluster = "${NUTANIX_CLUSTER_NAME}"
nutanix_subnet = "${NUTANIX_SUBNET_NAME}"
centos_disk_image_url = "$(cat /var/run/vault/assisted-ci-vault/centos_disk_image_url)"
image_name = "assisted-test-infra-machine-template"
ssh_public_key = "/var/run/vault/assisted-ci-vault/ssh_public_key"
ssh_private_key_file = "/var/run/vault/assisted-ci-vault/ssh_private_key"
EOF


# print config 
cat nutanix-params.hcl 


export PACKER_CONFIG_DIR=/home/assisted-test-infra/build/packer/config
export PACKER_CACHE_DIR=$PACKER_CONFIG_DIR/cache

sed -i "s#SSH_KEY_PLACEHOLDER#$(cat /var/run/vault/assisted-ci-vault/ssh_public_key)#g" cloud-config.yaml

packer.io init .
packer.io build -on-error=cleanup -var-file=nutanix-params.hcl .
