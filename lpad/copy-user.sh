#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) source_uid new_uid uid_number description"
  exit 1
}

NUM_EXPECTED_ARGS=5
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="copy-user.sh"
TEMP_FILE="copy-user.sh.RUNNING"
# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID="${3}"

# include the lpad-common script
source ./lpad-common.sh

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#SOURCE#" ${2}
lpad_arg "#UID#" ${USER_ID}
lpad_arg "#UID_NUMBER#" ${4}
lpad_arg "#DESC#" "${5}"
lpad_arg "#HASH5#" ${PMD5}
lpad_arg "#HASH6#" ${PSHA512}
lpad_arg "#PSHA#" ${PSHA}
lpad_arg "#PCRYPT#" ${PCRYPT}

# --------------------------------
# --  END STANDARD LPAD SCRIPT  --
# --------------------------------

# DO NOT ALTER BELOW THIS LINE

# do the swap
lpad_replacements
if [ $? -ne 0 ]; then echo "Error updating ${TEMP_FILE}"; exit 1; fi

# exec
lpad_exec
