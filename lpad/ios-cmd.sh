#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) device command1 [command2] [command3] [etc...]"
  exit 1
}

NUM_EXPECTED_ARGS=3
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="ios-cmd.exp"
TEMP_FILE="ios-cmd.RUNNING"
# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID=""

# include the lpad-common script
source ./lpad-common.sh

# prompt for credentials
read -p "User Name: " USERID
read -sp "Password: " PASSWD; echo
read -sp "Enable Password: " ENABLE; echo
if [[ -z $USERID || -z $PASSWD || -z $ENABLE ]]; then
  echo "Error: User, Password, and Enable can not be blank!" >&2
  exit 1
fi

# load commands
IOSCMD=""
for ((i=3;i<=$#;i++)); do
  if [ "$IOSCMD" == "" ]; then IOSCMD="${!i}"; else IOSCMD="${IOSCMD}%${!i}"; fi
done

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#COMMAND#" "${IOSCMD}"
lpad_arg "#USERID#" ${USERID}
lpad_arg "#PASSWD#" ${PASSWD}
lpad_arg "#ENABLE#" ${ENABLE}

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
