#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) source_user[@source_host] new_user[@new_host] [hash]"
  echo
  echo "You must provide both user IDs.  If you provide one host the other must be provided as well"
  exit 1
}

NUM_EXPECTED_ARGS=3
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="mysql-copy-user.sh"
TEMP_FILE="mysql-copy-user.sh.RUNNING"

# check whether or not the user id has a host
echo $2 |grep -q '@'
if [ $? -eq 0 ]; then
  echo $3 |grep -q '@'
  if [ $? -ne 0 ]; then
    echo "Error: You must provide a host for both users or neither."; exit 1
  fi
  USER_ID_LOAD=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\1/' )
  DUSER_ID=$( echo $3 |sed 's/\([^@]*\)@\(.*\)/\1/' )
  SHOST=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\2/' )
  DHOST=$( echo $3 |sed 's/\([^@]*\)@\(.*\)/\2/' )
else
  USER_ID_LOAD=$2
  DUSER_ID=$3
  SHOST=""
  DHOST=""
fi

# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
if [ $# -gt 3 ]; then USER_ID=""; else USER_ID=$DUSER_ID; fi

# include the lpad-common script
source ./lpad-common.sh

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#SOURCE_UID#" $USER_ID_LOAD
lpad_arg "#SOURCE_HOST#" $SHOST
lpad_arg "#DEST_UID#" $DUSER_ID
lpad_arg "#DEST_HOST#" $DHOST
if [ $# -eq 3 ]; then
  lpad_arg "#HASH#" ${PMYSQL}
else
  lpad_arg "#HASH#" $4
fi

# --------------------------------
# --  END STANDARD LPAD SCRIPT  --
# --------------------------------

# DO NOT ALTER BELOW THIS LINE

# do the swap
lpad_replacements
if [ $? -ne 0 ]; then echo "Error updating ${TEMP_FILE}"; exit 1; fi

# exec
lpad_exec

exit 0
