#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "Usage: $0 host(s) device(s) [filename] [--diff initials]"
  echo
  echo "      Filename is optional when diff is specified"
  echo "      Diff requires initials"
  exit 1
}

NUM_EXPECTED_ARGS=2
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="get-ios-config.exp"
TEMP_FILE="get-ios-config.RUNNING"
# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
USER_ID=""

# filename setting
FILENAME=${3}
FNOVERRIDE=0

# diff settings
if [[ $# -eq 5 && "$4" == "--diff" ]]; then
  DIFF=1; INITIALS=${5}
elif [[ $# -eq 4 && "$3" == "--diff" ]]; then
  DIFF=1; INITIALS=${4}; FNOVERRIDE=1
else
  DIFF=0; INITIALS=""
fi

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

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#USERID#" ${USERID}
lpad_arg "#PASSWD#" ${PASSWD}
lpad_arg "#ENABLE#" ${ENABLE}
lpad_arg "#DIFF#" $DIFF
lpad_arg "#INITIALS#" ${INITIALS}

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

  # filename override
  test $FNOVERRIDE -eq 1 && FILENAME="/tftpboot/${D}-config"

  # set the filename for this run
  SCRIPT_ARGUMENT_ARR[${C}]="#FILENAME#"
  SCRIPT_ARGUMENT_ARV[${C}]=${FILENAME}

  # set the device for this run
  SCRIPT_ARGUMENT_ARR[$(($C+1))]="#DEVICE#"
  SCRIPT_ARGUMENT_ARV[$(($C+1))]=${D}
 
  # do the swap
  lpad_replacements
  if [ $? -ne 0 ]; then echo "Error updating ${TEMP_FILE}"; exit 1; fi
  
  # exec
  lpad_exec
done
