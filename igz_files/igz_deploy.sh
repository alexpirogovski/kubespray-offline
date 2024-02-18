#!/bin/bash

# Exit on any error
set -e
. ./config.sh

BASEDIR="."
FILES_DIR=./files
KUBESPRAY_DIR_NAME=kubespray-$KUBESPRAY_VERSION
BASEDIR=$(cd $BASEDIR; pwd)
NGINX_IMAGE=iguazio/nginx_server:latest
RESET="no"
SKIP_INSTALL="no"
SCALE_OUT="no"
# Get the number of arguments
num_args=$#
# Get the last argument directly
SUDO_PASS="${!num_args}"
DEPLOYMENT_PLAYBOOK="cluster.yml"
LOCAL_REGISTRY=${LOCAL_REGISTRY:-"localhost:${REGISTRY_PORT}"}
if [ -f /etc/ansible/facts.d/haproxy.fact ]; then
    HAPROXY=$(grep 'enabled' /etc/ansible/facts.d/haproxy.fact | awk -F ' = ' '{print $2}') || HAPROXY="false"
else
    HAPROXY="false"
fi

###### Flow starts here ##########################

# Get the deploy options
for arg in "$@"
do
   if [ "$arg" == "--reset" ]; then
       echo "Reset was requested"
       RESET="yes"
   elif [ "$arg" == "--skip-k8s-install" ]; then
       echo "skip-k8s-install was requested"
       SKIP_INSTALL="yes"
   elif [ "$arg" == "--scale" ]; then
       echo "Scale out requested"
       SCALE_OUT="yes"
       DEPLOYMENT_PLAYBOOK="scale.yml"
   fi
done

# Verify deploy options
if [ "$SCALE_OUT" == "yes" ]; then
 RESET="no"
 SKIP_INSTALL="no"
fi

echo "==> Extract Kubespray"
./extract-kubespray.sh
# The files in kubespray dir are owned by root and we don't like it
#chown -R iguazio:iguazio .

echo "==> Install python3.9 on controller"
if ! command -v python3.9 &> /dev/null; then
  echo $SUDO_PASS | sudo -S rpm -ivh rpms/python39-3.9.16-standalone.el7.x86_64.rpm
fi

echo "==> Copy pushing script"
chmod +x igz_push.py
echo $SUDO_PASS | sudo -S cp igz_push.py /usr/local/bin/

echo "==> Create venv and install requirements"
python3.9 -m venv venv
echo "######## Working in venv ########"
. venv/bin/activate
python -m pip install --no-index --find-links=k8s_requirements -r requirements.txt

echo "==> Build Iguazio inventory"
python3 ./igz_inventory_builder.py "${@: -4}" "$HAPROXY"

# Don't stop containers in case of scale out - it's a live data node!
if [ "$SCALE_OUT" == "yes" ]; then
  echo -e "\n# Live system flag\nlive_system: true" >> igz_override.yml
else
  echo -e "\n# Live system flag\nlive_system: false" >> igz_override.yml
fi

echo "==> Prepare inventory dir"
pushd ./$KUBESPRAY_DIR_NAME
cp -r inventory/sample inventory/igz
# Copy and rename file in one line
cat ../igz_offline.yml > inventory/igz/group_vars/all/offline.yml
cp ../igz_inventory.ini ./inventory/igz

echo "==> Copy Iguazio files"
find ../ -maxdepth 1 -type f -name 'igz_*' -exec cp '{}' . ';'

# Copy playbook for offline repo
cp -r ../playbook .

# Run igz_preinstall playbook
ansible-playbook -i inventory/igz/igz_inventory.ini igz_pre_install.yml --become --extra-vars=@igz_override.yml

# Run offline repo playbook
ansible-playbook -i inventory/igz/igz_inventory.ini playbook/offline-repo.yml --become --extra-vars=@igz_override.yml

# Reset Kubespray
if [[ "${RESET}" == "yes" ]]; then
  echo "==> Reset Kubernetes"
  ansible-playbook -i inventory/igz/igz_inventory.ini reset.yml --become --extra-vars=@igz_override.yml --extra-vars reset_confirmation=yes
  ansible-playbook -i inventory/igz/igz_inventory.ini igz_reset.yml --become --extra-vars=@igz_override.yml
fi

# Run kubespray
if [[ "${SKIP_INSTALL}" == "no" ]]; then
    echo "==> Install  Kubernetes"
    ansible-playbook -i inventory/igz/igz_inventory.ini $DEPLOYMENT_PLAYBOOK --become --extra-vars=@igz_override.yml
    ansible-playbook -i inventory/igz/igz_inventory.ini igz_post_install.yml --become --extra-vars=@igz_override.yml
fi

popd
deactivate
echo "######## venv deactivated ########"

echo "<=== Kubespray deployed. Happy k8s'ing ===>"
exit 0
