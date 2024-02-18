#!/bin/bash

# Exit on any error
set -e

. config.sh

KUBESPRAY_DIR=./cache/kubespray-${KUBESPRAY_VERSION}
PATCH_DIR=/target-scripts/patches/${KUBESPRAY_VERSION}

# Copy igz_patches to target-scripts/patches
if [[ -d "./igz_patches/${KUBESPRAY_VERSION}" ]]; then
  mkdir -p ${PATCH_DIR}
  find ./igz_patches/${KUBESPRAY_VERSION}/ -type f -exec cp {} $PATCH_DIR/ \;
else
  echo "[INFO]: No igz patches provided for the current release ${KUBESPRAY_VERSION}"
fi

# Run the flow
./precheck.sh
./prepare-pkgs.sh
./prepare-py.sh
./get-kubespray.sh
./pypi-mirror.sh
./download-kubespray-files.sh
./create-repo.sh
./copy-target-scripts.sh
#./download-additional-containers.sh

echo "===> Fetch requirements.txt"
cp $KUBESPRAY_DIR/requirements.txt .

echo "==> Download python3.9 RPM"
wget -P /outputs/rpms https://artifactory.iguazeng.com:443/artifactory/iguazio-devops/opt_packages/centos7/python39-3.9.16-standalone.el7.x86_64.rpm

echo "Download k8s requirements"
mkdir -p /outputs/k8s_requirements
python3.9 -m pip download -r requirements.txt -d /outputs/k8s_requirements

echo "===> Fetch Iguazio scripts"
find . -path './proc' -prune -o -type f -name "igz_*" -exec cp {} /outputs/ \;

chown -R 1000:1000 /outputs

echo "<=== Kubespray $KUBESPRAY_VERSION is ready for offline deployment ===>"
exit 0
