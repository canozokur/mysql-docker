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
CONFIG_PACKAGE_NAME_MINIMAL=mysql-community-minimal-release-el8.rpm; [ -n "$3" ] && CONFIG_PACKAGE_NAME_MINIMAL=$3

REPO_NAME_SERVER=mysql80-community-minimal; [ -n "$4" ] && REPO_NAME_SERVER=$4
REPO_NAME_TOOLS=mysql-tools-community; [ -n "$5" ] && REPO_NAME_TOOLS=$5

MYSQL_SERVER_PACKAGE_NAME="mysql-community-server-minimal"; [ -n "$6" ] && MYSQL_SERVER_PACKAGE_NAME=$6
MYSQL_SHELL_PACKAGE_NAME="mysql-shell"; [ -n "$7" ] && MYSQL_SHELL_PACKAGE_NAME=$7
MYSQL_VERSION=""; [ -n "$8" ] && MYSQL_VERSION=$8
# 33060 is the default port for the mysqlx plugin, new to 5.7
declare -A PORTS
PORTS["5.7"]="3306 33060"
PORTS["8.0"]="3306 33060 33061"

declare -A PASSWORDSET
PASSWORDSET["5.7"]="ALTER USER 'root'@'localhost' IDENTIFIED BY '\${MYSQL_ROOT_PASSWORD}';"
PASSWORDSET["8.0"]=${PASSWORDSET["5.7"]}

# MySQL 8.0 supports a call to validate the config, while older versions have it as a side
# effect of running --verbose --help
declare -A VALIDATE_CONFIG
VALIDATE_CONFIG["5.7"]="output=\$(\"\$@\" --verbose --help 2>\&1 > /dev/null) || result=\$?"
VALIDATE_CONFIG["8.0"]="output=\$(\"\$@\" --validate-config) || result=\$?"

# Data directories that must be created with special ownership and permissions when the image is built
declare -A PRECREATE_DIRS
PRECREATE_DIRS["5.7"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
PRECREATE_DIRS["8.0"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"

for VERSION in "${!MYSQL_SERVER_VERSIONS[@]}"
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
  if [ "${VERSION}" == "5.7" ]; then
    sed -i 's#%%PORTS%%#'"3306/tcp, 33060/tcp"'#g' tmpFile
  else
    sed -i 's#%%PORTS%%#'"3306/tcp, 33060-33061/tcp"'#g' tmpFile
  fi
  mv tmpFile "${VERSION}/inspec/control.rb"

  # Entrypoint
  sed 's#%%PASSWORDSET%%#'"${PASSWORDSET[${VERSION}]}"'#g' template/docker-entrypoint.sh > tmpfile
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
