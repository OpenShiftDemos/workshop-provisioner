#!/bin/bash

set -x

PROJECTNAME=workshop-infra
GITLABHOSTNAME=gitlab-ce.$PROJECTNAME.svc.cluster.local
GITLABEXTHOSTNAME=gitlab-ce-$PROJECTNAME.$APPS_DOMAIN
export NEXUS_BASE_URL=nexus.$PROJECTNAME.svc.cluster.local:8081

# login as user with admin permissions
oc login --insecure-skip-tls-verify=true $MASTER_URL -u $ADMINUSER -p $ADMINPASSWORD

# create nexus project
oc adm new-project workshop-infra --admin $ADMINUSER --node-selector='env=infra'

# set scc for anyuid
oc adm policy add-scc-to-group hostmount-anyuid system:serviceaccounts:workshop-infra

# switch to workshop-infra project
oc project workshop-infra

# deploy the lab document server
oc new-app --name=labs https://github.com/openshift-evangelists/openshift-workshops.git
oc expose service labs

# create gitlab
oc process -f gitlab-template.yaml -v APPLICATION_HOSTNAME=$GITLABEXTHOSTNAME -v GITLAB_ROOT_PASSWORD=password | oc create -f -

# wait for gitlab to be ready
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

  if [ $x -gt 10 ]
  then
    exit 255
  fi

  oc get ep nexus -o yaml | grep "\- addresses:"
done

# add redhat repo for nexus
bash addrepo.sh redhat-ga https://maven.repository.redhat.com/ga/

# add jboss repo for nexus
bash addrepo.sh jboss https://repository.jboss.org/nexus/content/repositories/public

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
git clone https://github.com/openshift-roadshow/nationalparks repos/nationalparks
git clone https://github.com/openshift-roadshow/mlbparks repos/mlbparks
git clone https://github.com/openshift-roadshow/parksmap-web repos/parksmap-web
mvn -s maven.xml -f repos/parksmap-web/pom.xml install
mvn -s maven.xml -f repos/mlbparks/pom.xml install
mvn -s maven.xml -f repos/nationalparks/pom.xml install
