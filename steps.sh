#!/bin/bash

set -x

#blueprint
#* create admin user (in blueprint)
#* create /var/gitlab/vol1,2
#* set selinux context to system_u:object_r:svirt_sandbox_file_t:s0
#deployer

PROJECTNAME=workshop-infra

# login as user with admin permissions
oc login https://$MASTERHOST:$MASTERPORT -u $ADMINUSER -p $ADMINPASSWORD

# create nexus project
oc adm new-project workshop-infra --admin $ADMINUSER --node-selector='env=infra'

# set scc for anyuid
oc adm policy add-scc-to-group anyuid system:serviceaccounts:workshop-infra

# switch to workshop-infra project
oc project workshop-infra

# create gitlab
oc process -f gitlab-template.yaml -v APPLICATION_HOSTNAME=gitlab-$PROJECTNAME.$CLOUDDOMAIN -v GITLAB_ROOT_PASSWORD=password | oc create -f -
