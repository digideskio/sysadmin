#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) user[@host]"
  echo
  exit 1
}

NUM_EXPECTED_ARGS=2
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="mysql-drop-user.sh"
TEMP_FILE="mysql-drop-user.sh.RUNNING"

# check whether or not the user id has a host
echo $2 |grep -q '@'
if [ $? -eq 0 ]; then
  SUSER=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\1/' )
  SHOST=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\2/' )
else
  SUSER=$2
  SHOST=""
fi

# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID=""

# include the lpad-common script
source ./lpad-common.sh

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#USER_ID#" $SUSER
lpad_arg "#HOST#" $SHOST

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
