#!/bin/bash

set -x

#master
#htpasswd -b /etc/origin/openshift-passwd admin somepassword
#oc adm policy add-cluster-role-to-user cluster-admin admin
#
#infra
#mkdir -p /var/{gitlab/vol1,gitlab/vol2,nexus}
#chmod -R 777 /var/gitlab
#chown -R 200:200 /var/nexus
#chcon -R system_u:object_r:svirt_sandbox_file_t:s0 /var/nexus
#chcon -R system_u:object_r:svirt_sandbox_file_t:s0 /var/gitlab

PROJECTNAME=workshop-infra
GITLABHOSTNAME=gitlab-$PROJECTNAME.$CLOUDDOMAIN
NEXUS_BASE_URL=nexus-$PROJECTNAME.$CLOUDDOMAIN

# login as user with admin permissions
oc login --insecure-skip-tls-verify=true https://$MASTERHOST:$MASTERPORT -u $ADMINUSER -p $ADMINPASSWORD

# create nexus project
oc adm new-project workshop-infra --admin $ADMINUSER --node-selector='env=infra'

# set scc for anyuid
oc adm policy add-scc-to-group hostmount-anyuid system:serviceaccounts:workshop-infra

# switch to workshop-infra project
oc project workshop-infra

# create gitlab
oc process -f gitlab-template.yaml -v APPLICATION_HOSTNAME=$GITLABHOSTNAME -v GITLAB_ROOT_PASSWORD=password | oc create -f -

# wait for gitlab to be ready - it's really slow because the image is big and it's just slow in our environment
x=1
oc get ep gitlab-ce -o yaml | grep "\- addresses:"
while [ ! $? -eq 0 ]
do
  sleep 60
  x=$(( $x + 1 ))

  if [ $x -gt 10 ]
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

# instantiate nexus
oc create -f nexus.yaml

# wait for nexus to be ready
x=1
oc get ep nexus -o yaml | grep "\- addresses:"
while [ ! $? -eq 0 ]
do
  sleep 60
  x=$(( $x + 1 ))

  if [ $x -gt 5 ]
  then
    exit 255
  fi

  oc get ep nexus -o yaml | grep "\- addresses:"
done

# add redhat repo for nexus
NEXUS_BASE_URL=nexus-$PROJECTNAME.$CLOUDDOMAIN bash addrepo.sh redhat-ga https://maven.repository.redhat.com/ga/

NEXUS_BASE_URL=nexus-$PROJECTNAME.$CLOUDDOMAIN 

# generate the maven settings file
cat << EOF > maven.xml
<settings>
    <mirrors>
        <mirror>
            <id>nexus</id>
            <mirrorOf>*</mirrorOf>
            <url>http://$NEXUS_BASE_URL/content/groups/public</url>
        </mirror>
    </mirrors>
</settings>
EOF

# prime nexus by cleaning
rm -rf ~/.m2/repository/
mkdir repos
git clone https://github.com/jorgemoralespou/ose3-parks repos/ose3-parks
git clone https://github.com/gshipley/openshift3mlbparks repos/openshift3mlbparks
mvn -s maven.xml -f repos/ose3-parks/mlbparks-mongo/pom.xml install
mvn -s maven.xml -f repos/ose3-parks/web-parksmap/pom.xml install
mvn -s maven.xml -f repos/openshift3mlbparks/pom.xml install
