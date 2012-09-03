#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) uid uid_number"
  exit 1
}

NUM_EXPECTED_ARGS=3
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="change-uid.sh"
TEMP_FILE="change-uid.sh.RUNNING"
# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID=""

# include the lpad-common script
source ./lpad-common.sh

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#UID#" ${2}
lpad_arg "#UID_NUMBER#" ${3}

# --------------------------------
# --  END STANDARD LPAD SCRIPT  --
# --------------------------------

# DO NOT ALTER BELOW THIS LINE

# do the swap
lpad_replacements
if [ $? -ne 0 ]; then echo "Error updating ${TEMP_FILE}"; exit 1; fi

# exec
lpad_exec

echo 'press ctrl+c to exit'
sleep 99999
