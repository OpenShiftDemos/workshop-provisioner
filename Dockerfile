FROM centos:7

MAINTAINER Erik Jacobs <erikmjacobs@gmail.com>

USER root
RUN yum clean all && \
    export INSTALL_PKGS="maven jq origin-clients-1.2.1-1.el7 java-1.8.0-openjdk-devel" && \
    yum clean all && \
    yum -y --setopt=tsflags=nodocs install epel-release centos-release-openshift-origin && \
    yum install -y --setopt=tsflags=nodocs install $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all 
ADD files /root/

WORKDIR /root/
ENTRYPOINT bash steps.sh
