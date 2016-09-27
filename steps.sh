#!/bin/bash

set -x

#blueprint
#* create admin user (in blueprint)
#* create /var/gitlab/vol1,2
#* set selinux context to system_u:object_r:svirt_sandbox_file_t:s0
#deployer

PROJECTNAME=workshop-infra
GITLABHOSTNAME=gitlab-$PROJECTNAME.$CLOUDDOMAIN

# login as user with admin permissions
oc login https://$MASTERHOST:$MASTERPORT -u $ADMINUSER -p $ADMINPASSWORD

# create nexus project
oc adm new-project workshop-infra --admin $ADMINUSER --node-selector='env=infra'

# set scc for anyuid
oc adm policy add-scc-to-group anyuid system:serviceaccounts:workshop-infra

# switch to workshop-infra project
oc project workshop-infra

# create gitlab
oc process -f gitlab-template.yaml -v APPLICATION_HOSTNAME=$GITLABHOSTNAME -v GITLAB_ROOT_PASSWORD=password | oc create -f -

# wait for gitlab to be ready
x=1
oc get ep gitlab-ce -o yaml | grep "\- addresses:"
while [ ! $? -eq 0 ]
do
  sleep 30
  x=$(( $x + 1 ))

  if [ $x -gt 8 ]
  then
    exit 255
  fi

  oc get ep gitlab-ce -o yaml | grep "\- addresses:"
done

# get a token from GitLab to use with the API
# requires JQ package!
TOKEN_ROOT=$(curl -Ls http://$GITLABHOSTNAME/api/v3/session --data 'login=root&password=password' | jq -r .private_token)

# create users
for x in $(seq -f %02g 1 $NUMUSERS)
do
  curl -X POST -H "PRIVATE-TOKEN: $TOKEN_ROOT" -H "Expect:" -F confirm=false \
  -F email=user$x@example.com -F username=user$x -F name=user$x -F password=password \
  "http://$GITLABHOSTNAME/api/v3/users"
done

# bring in external git repos for created users
for x in $(seq -f %02g 1 $NUMUSERS)
do
  TOKEN_DEV=$(curl -Ls http://$GITLABHOSTNAME/api/v3/session --data "login=user$x&password=password" | jq -r .private_token)
  
  curl --header "PRIVATE-TOKEN: ${TOKEN_DEV}" -X POST http://$GITLABHOSTNAME/api/v3/projects \
  --data-urlencode "name=openshift3nationalparks" \
  --data-urlencode "import_url=https://gitlab.com/jorgemoralespou/openshift3nationalparks" \
  --data-urlencode "public=true"
done
