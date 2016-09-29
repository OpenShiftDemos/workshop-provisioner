#!/bin/bash
set -x

# master
ssh root@master1.example.com "htpasswd -b /etc/origin/openshift-passwd admin somepassword"
ssh root@master1.example.com "oc adm policy add-cluster-role-to-user cluster-admin admin"

# infra
ssh root@infranode1.example.com "mkdir -p /var/{gitlab/vol1,gitlab/vol2,nexus}"
ssh root@infranode1.example.com "chmod -R 777 /var/gitlab"
ssh root@infranode1.example.com "chown -R 200:200 /var/nexus"
ssh root@infranode1.example.com "chcon -R system_u:object_r:svirt_sandbox_file_t:s0 /var/nexus"
ssh root@infranode1.example.com "chcon -R system_u:object_r:svirt_sandbox_file_t:s0 /var/gitlab"

# provisioner
# make sure we're in the default project -- just in case
ssh root@master1.example.com oc project default
ssh root@master1.example.com oc run workshop-provisioner --restart=Never \
--env="ADMINUSER=admin" --env="ADMINPASSWORD=somepassword" --env="BASEDOMAIN=$GUID.oslab.opentlc.com" \
--env="MASTERPORT=8443" --env="NUMUSERS=5" --image=openshiftdemos/workshop-provisioner:0.14
set +x
