#!/bin/sh

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) uid"
  exit 1
}

NUM_EXPECTED_ARGS=2
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="reset-passwd.sh"
TEMP_FILE="reset-passwd.sh.RUNNING"
# set USER_ID to an empty string if you do not need password
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID="${2}"

# include the lpad-common script
source ./lpad-common.sh

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#UID#" ${USER_ID}
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

#exec
lpad_exec
