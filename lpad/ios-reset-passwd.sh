#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) device(s) userid"
  exit 1
}

NUM_EXPECTED_ARGS=3
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="ios-reset-passwd.exp"
TEMP_FILE="ios-reset-passwd.RUNNING"
# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID="${3}"

# include the lpad-common script
source ./lpad-common.sh

# prompt for credentials
read -p "Auth User Name: " USERID
read -sp "Auth Password: " PASSWD; echo
read -sp "Enable Password: " ENABLE; echo
if [[ -z $USERID || -z $PASSWD || -z $ENABLE ]]; then
  echo "Error: User, Password, and Enable can not be blank!" >&2
  exit 1
fi
echo

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#AUTH_ID#" ${USERID}
lpad_arg "#AUTH_PWD#" ${PASSWD}
lpad_arg "#ENABLE#" ${ENABLE}
lpad_arg "#HASH#" $(echo ${PMD5_CISCO} |sed 's%\$%\\\\$%g')
lpad_arg "#USERID#" ${3}

# --------------------------------
# --  END STANDARD LPAD SCRIPT  --
# --------------------------------

# DO NOT ALTER BELOW THIS LINE
# whatevs

# get the count to put the device at
C=${#SCRIPT_ARGUMENT_ARR[@]}

for D in ${2}; do
  # output status
  echo -n "[${D}]@"

  # set the device for this run
  SCRIPT_ARGUMENT_ARR[${C}]="#DEVICE#"
  SCRIPT_ARGUMENT_ARV[${C}]=${D}
 
  # do the swap
  lpad_replacements
  if [ $? -ne 0 ]; then echo "Error updating ${TEMP_FILE}"; exit 1; fi
  
  # exec
  lpad_exec
done
