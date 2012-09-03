#!/bin/sh

# common launchpad include script

function lpad_arg {
  # add an argument to the script arg array
  if [ "${1}" == "" ]; then return 1; fi
  SCRIPT_ARGUMENT_ARR[${#SCRIPT_ARGUMENT_ARR[@]}]="${1}"
  SCRIPT_ARGUMENT_ARV[${#SCRIPT_ARGUMENT_ARV[@]}]="${2}"
  return 0
}

function lpad_exec {
  # validate the file name
  VSOURCE=`/bin/basename ${SOURCE_FILE}`
  # set a temp folder name to use on the remote server
  TEMP_PATH="/usr/local/etc/lpad-exec.$$"
  # execute the run
  for SYS in `echo "${PASSED_HOSTS}" | sed 's/ /\n/g'`; do
    echo "[${SYS}]"
    scp ${TEMP_FILE} ${SYS}:/tmp/${VSOURCE} >/dev/null 2>&1
    ssh -n ${SYS} "mkdir -m 0700 -p ${TEMP_PATH}; cd ${TEMP_PATH}; \
      mv /tmp/${VSOURCE} .; chmod +x ${VSOURCE}; ./${VSOURCE} ; cd /; \
      rm -rf ${TEMP_PATH}"
    echo "--------------------------------------------------------------------------------"
  done
  # cleanup
  rm -f ${TEMP_FILE}
  return 0
}

function lpad_replacements {
  # make the file replacements
  cp ./scripts/${SOURCE_FILE} ${TEMP_FILE}
  if [ ! -f ${TEMP_FILE} ]; then return 1; fi
  for (( i=0;i<${#SCRIPT_ARGUMENT_ARR[@]};i++ )); do
    VALUE="`echo ${SCRIPT_ARGUMENT_ARV[$i]} | sed -e 's/[%&]/\\\\&/g'`"
    sed -i "s%${SCRIPT_ARGUMENT_ARR[$i]}%${VALUE}%g" ${TEMP_FILE}
  done
  return 0
}

# set variables
HASH_FILE=".hash"
TAB=$'\t'
SCRIPT_ARGUMENT_ARR=()
SCRIPT_ARGUMENT_ARV=()

# check for arguments
if [ $# -lt ${NUM_EXPECTED_ARGS} ]; then usage; fi

# ensure script runs just once
if [ -f ${TEMP_FILE} ]; then
  echo "Error: another instance is running or exited improperly!"
  exit 1
fi

# make sure the hash file exists
if [ ! -f ${HASH_FILE} ]; then
  echo "Error: hash file does not exist"; exit 1
fi

# process the host list
source ./host-parser.sh "${INP_HOSTS}"

# make sure the user has hashes
if [ "${USER_ID}" != "" ]; then
  egrep "^${USER_ID}${TAB}" ${HASH_FILE} 2>&1 1>/dev/null
  if [ $? -ne 0 ]; then
    /bin/sh gen-hash.sh ${USER_ID}
    if [ $? -ne 0 ]; then exit 1; fi
  fi
  
  # get the hashes from the file
  LINE=`grep "^${USER_ID}${TAB}" ${HASH_FILE}`
  PMD5=`echo ${LINE} | awk '{ print $4 }'`
  PSHA512=`echo ${LINE} | awk '{ print $5 }'`
  PMYSQL=`echo ${LINE} | awk '{ print $2 }'`
  PMYSQL_OLD=`echo ${LINE} | awk '{ print $3 }'`
  PCRYPT=`echo ${LINE} | awk '{ print $6 }'`
  PSHA=`echo ${LINE} | awk '{ print $7 }'`
  PMD5_BASIC=`echo ${LINE} | awk '{ print $8 }'`
  PMD5_CISCO=`echo ${LINE} | awk '{ print $9 }'`
fi
