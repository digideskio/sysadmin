#!/bin/bash

# --------------------------------
# -- BEGIN STANDARD LPAD SCRIPT --
# --     UPDATE AS NEEDED       --
# --------------------------------

function usage {
  echo "
Usage: $0 host(s) user[@host] [hash] [/path/to/password] [--skip-db]

       You must provide a user id.
       If you provide a hash the saved hashes will not be consulted.

       IN ORDER TO RESET root YOU MUST provide the path to a file with one line
         containing the plain text password.
       If you provide the plain text password you must also provide the hash.

       This file should be a temporary file with permissions 600 and owned by root
         or it will not be consulted.  This script will delete the temp file you provide!

       Skip DB can only be provided if all other arguments are provided. It is
       used specifically for resetting root passwords on slaves where the mysql
       database is propagated from the master.  It causes the reset script to
       only update /root/.my.cnf and reload sqlkiller (if applicable).
"
  exit 1
}

NUM_EXPECTED_ARGS=2
INP_HOSTS="${1}"
# source file has to just be the file name due to the
#   way the variable is used in the lpad_exec function
SOURCE_FILE="mysql-reset-passwd.sh"
TEMP_FILE="mysql-reset-passwd.sh.RUNNING"

# check whether or not the user id has a host
echo $2 |grep -q '@'
if [ $? -eq 0 ]; then
  USER_ID_LOAD=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\1/' )
  DHOST=$( echo $2 |sed 's/\([^@]*\)@\(.*\)/\2/' )
else
  USER_ID_LOAD=$2
  DHOST=""
fi

# set USER_ID to an empty string if you do not need password 
#   hashes for a specific account otherwise the variables
#   PMD5,PSHA512,PMYSQL,PMYSQL_OLD,PCRYPT,PSHA,PMD5_BASIC
#   will be provided
if [ $# -gt 2 ]; then USER_ID=""; else USER_ID=$USER_ID_LOAD; fi

# include the lpad-common script
source ./lpad-common.sh

if [ $# -gt 2 ]; then USER_ID=$USER_ID_LOAD; fi

# load the plaintext password if one is set
if [ $# -gt 3 ]; then
  if [ ! -f $4 ]; then echo "Error: '$4' does not exist!"; exit 1; fi
  if [ "`stat -c%U%a $4`" != "root600" ]; then
    echo "Error: '$4' must be owned by root and chmod 600!"; exit 1
  fi
  PASSWD=$( head -n1 $4 )
  if [ "$PASSWD" == "" ]; then echo "Error: empty password from '$4'!"; exit 1; fi
  /bin/rm -f $4
fi

# add arguments to be swapped out in the source file
# lpad_arg "#REPLACEMENT#" "VALUE"
lpad_arg "#UID#" $USER_ID
lpad_arg "#HOST#" $DHOST
lpad_arg "#PASSWD#" $PASSWD
if [ $# -eq 2 ]; then
  lpad_arg "#HASH#" $PMYSQL
else
  lpad_arg "#HASH#" $3
fi
if [[ $# -eq 5 && "$5" == "--skip-db" ]]; then
  lpad_arg "#SKIPDB#" 1
else
  lpad_arg "#SKIPDB#" 0
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
