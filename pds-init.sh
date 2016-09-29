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

set +x
