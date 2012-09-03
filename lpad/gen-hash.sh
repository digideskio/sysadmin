#!/bin/sh

# generate user hashes
#
# requires the user id
#

if [[ $# -ne 1 || "${1}" == "" ]]; then
  echo "Usage: $0 uid"; exit 1
fi

ID="${1}"
FILE=".hash"
TAB=$'\t'

if [ ! -f ${FILE} ]; then
  echo "Error: hash file does not exist"; exit 1
fi

# make sure the user is not already set
egrep "^${ID}${TAB}" ${FILE} 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
  echo "Error: user account already has hashes, please remove them and try again."; exit 1
fi

# get the credentials
source ../syspasswd.sh

echo ${ID}$'\t'${PMYSQL}$'\t'${PMYSQL_OLD}$'\t'${PMD5}$'\t'${PSHA512}$'\t'${PCRYPT}$'\t'${PSHA}$'\t'${PMD5_BASIC}$'\t'${PMD5_CISCO}$'\t'${PSHA_SIMPLE} >> ${FILE}
chown root. ${FILE}
chmod 0600 ${FILE}
echo 'Done.'
