#!/bin/bash
# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

set -e

# This script will simply use sed to replace placeholder variables in the
# files in template/ with version-specific variants.

source ./VERSION

REPO=https://repo.mysql.com; [ -n "$1" ] && REPO=$1
CONFIG_PACKAGE_NAME=mysql80-community-release-el8.rpm; [ -n "$2" ] && CONFIG_PACKAGE_NAME=$2
CONFIG_PACKAGE_NAME_MINIMAL=mysql-cluster-community-minimal-release-el8.rpm; [ -n "$3" ] && CONFIG_PACKAGE_NAME_MINIMAL=$3

REPO_NAME_SERVER=mysql-cluster80-community-minimal; [ -n "$4" ] && REPO_NAME_SERVER=$4
REPO_NAME_TOOLS=mysql-tools-community; [ -n "$5" ] && REPO_NAME_TOOLS=$5

MYSQL_SERVER_PACKAGE_NAME="mysql-cluster-community-server-minimal"; [ -n "$6" ] && MYSQL_SERVER_PACKAGE_NAME=$6
MYSQL_SHELL_PACKAGE_NAME="mysql-shell"; [ -n "$7" ] && MYSQL_SHELL_PACKAGE_NAME=$7
MYSQL_VERSION=""; [ -n "$8" ] && MYSQL_VERSION=$8

declare -A PORTS
PORTS["7.5"]="3306 33060 2202 1186"
PORTS["7.6"]="3306 33060 2202 1186"
PORTS["8.0"]="3306 33060-33061 2202 1186"

declare -A PASSWORDSET
PASSWORDSET["7.5"]="ALTER USER 'root'@'localhost' IDENTIFIED BY '\${MYSQL_ROOT_PASSWORD}';"
PASSWORDSET["7.6"]=${PASSWORDSET["7.5"]}
PASSWORDSET["8.0"]=${PASSWORDSET["7.6"]}

declare -A DATABASE_INIT
DATABASE_INIT["7.5"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"
DATABASE_INIT["7.6"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"
DATABASE_INIT["8.0"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"

declare -A STARTUP
STARTUP["7.5"]="exec \"\$@\" --user=\$MYSQLD_USER"
STARTUP["7.6"]="exec \"\$@\" --user=\$MYSQLD_USER"
STARTUP["8.0"]="export MYSQLD_PARENT_PID=\$\$ ; exec \"\$@\" --user=$MYSQLD_USER"


declare -A STARTUP_WAIT
STARTUP_WAIT["7.5"]="\"\""
STARTUP_WAIT["7.6"]="\"\""


# MySQL 8.0 supports a call to validate the config, while older versions have it as a side
# effect of running --verbose --help
declare -A VALIDATE_CONFIG
VALIDATE_CONFIG["7.5"]="output=\$(\"\$@\" --verbose --help 2>\&1 > /dev/null) || result=\$?"
VALIDATE_CONFIG["7.6"]="output=\$(\"\$@\" --verbose --help 2>\&1 > /dev/null) || result=\$?"
VALIDATE_CONFIG["8.0"]="output=\$(\"\$@\" --validate-config) || result=\$?"

# Data directories that must be created with special ownership and permissions when the image is built
declare -A PRECREATE_DIRS
PRECREATE_DIRS["7.5"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
PRECREATE_DIRS["7.6"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
PRECREATE_DIRS["8.0"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"

for VERSION in "${!MYSQL_CLUSTER_VERSIONS[@]}"
do
  if [ -n "${MYSQL_VERSION}" ]; then
    MYSQL_SERVER_PACKAGE=${MYSQL_SERVER_PACKAGE_NAME}-${MYSQL_VERSION}
    MYSQL_SHELL_PACKAGE=${MYSQL_SHELL_PACKAGE_NAME}-${MYSQL_VERSION}
  else
    MYSQL_SERVER_PACKAGE=${MYSQL_SERVER_PACKAGE_NAME}
    MYSQL_SHELL_PACKAGE=${MYSQL_SHELL_PACKAGE_NAME}
  fi
  # Dockerfiles
  MYSQL_SERVER_REPOPATH=yum/mysql-$VERSION-community/docker/x86_64
  DOCKERFILE_TEMPLATE=template/Dockerfile
  if [ "${VERSION}" != "8.0" ]; then
    DOCKERFILE_TEMPLATE=template/Dockerfile-pre8
  fi
  sed 's#%%MYSQL_SERVER_PACKAGE%%#'"${MYSQL_SERVER_PACKAGE}"'#g' $DOCKERFILE_TEMPLATE > tmpfile
  sed -i 's#%%REPO%%#'"${REPO}"'#g' tmpfile
  REPO_VERSION=${VERSION//\./}
  sed -i 's#%%REPO_VERSION%%#'"${REPO_VERSION}"'#g' tmpfile

  sed -i 's#%%CONFIG_PACKAGE_NAME%%#'"${CONFIG_PACKAGE_NAME}"'#g' tmpfile
  sed -i 's#%%CONFIG_PACKAGE_NAME_MINIMAL%%#'"${CONFIG_PACKAGE_NAME_MINIMAL}"'#g' tmpfile
  sed -i 's#%%REPO_NAME_SERVER%%#'"${REPO_NAME_SERVER}"'#g' tmpfile
  sed -i 's#%%REPO_NAME_TOOLS%%#'"${REPO_NAME_TOOLS}"'#g' tmpfile

  if [[ ! -z ${MYSQL_SHELL_VERSIONS[${VERSION}]} ]]; then
    sed -i 's#%%MYSQL_SHELL_PACKAGE%%#'"${MYSQL_SHELL_PACKAGE}"'#g' tmpfile
  else
    sed -i 's#%%MYSQL_SHELL_PACKAGE%%#'""'#g' tmpfile
  fi

  sed -i 's/%%PORTS%%/'"${PORTS[${VERSION}]}"'/g' tmpfile
  mv tmpfile ${VERSION}/Dockerfile

  # Dockerfile_spec.rb
  if [ ! -d "${VERSION}/inspec" ]; then
    mkdir "${VERSION}/inspec"
  fi
  sed 's#%%MYSQL_VERSION%%#'"${MYSQL_VERSION}"'#g' template/control.rb > tmpFile
  sed -i 's#%%MYSQL_SERVER_PACKAGE_NAME%%#'"${MYSQL_SERVER_PACKAGE_NAME}"'#g' tmpFile
  sed -i 's#%%MYSQL_SHELL_PACKAGE_NAME%%#'"${MYSQL_SHELL_PACKAGE_NAME}"'#g' tmpFile
  sed -i 's#%%MAJOR_VERSION%%#'"${VERSION}"'#g' tmpFile
  if [ "${VERSION}" == "8.0" ]; then
    sed -i 's#%%PORTS%%#'"1186/tcp, 2202/tcp, 3306/tcp, 33060-33061/tcp"'#g' tmpFile
  else
    sed -i 's#%%PORTS%%#'"1186/tcp, 2202/tcp, 3306/tcp, 33060/tcp"'#g' tmpFile
  fi
  mv tmpFile "${VERSION}/inspec/control.rb"

  # Entrypoint
  sed 's#%%PASSWORDSET%%#'"${PASSWORDSET[${VERSION}]}"'#g' template/docker-entrypoint.sh > tmpfile
  sed -i 's#%%STARTUP%%#'"${STARTUP[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%FULL_SERVER_VERSION%%#'"${FULL_SERVER_VERSIONS[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%VALIDATE_CONFIG%%#'"${VALIDATE_CONFIG[${VERSION}]}"'#g' tmpfile
  mv tmpfile ${VERSION}/docker-entrypoint.sh
  chmod +x ${VERSION}/docker-entrypoint.sh

  # Healthcheck
  cp template/healthcheck.sh ${VERSION}/
  chmod +x ${VERSION}/healthcheck.sh

  # Build-time preparation script
  sed 's#%%PRECREATE_DIRS%%#'"${PRECREATE_DIRS[${VERSION}]}"'#g' template/prepare-image.sh > tmpfile
  mv tmpfile ${VERSION}/prepare-image.sh
  chmod +x ${VERSION}/prepare-image.sh
done
