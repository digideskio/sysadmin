#!/bin/sh

# change a linux uid for an existing account
#
# requires:
#   #UID#           user id
#   #UID_NUMBER#    new user id number
#

# verify replacement has been made
echo '#UID# #UID_NUMBER#' | egrep '^#.*#$' >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Error: Substitution not made. Do not run this script directly."
  exit 1
fi

# clear troublesome variables
unset CDPATH

# only continue if the account exists
egrep -q '^#UID#' /etc/passwd >/dev/null 2>&1
if [ $? -ne 0 ]; then exit 0; fi

# test the uid number
C=`egrep '^#UID#:' /etc/passwd | awk 'BEGIN { FS=":" } { print $3 }'`
if [ "$C" == "#UID_NUMBER#" ]; then echo "UID is correct, nothing to do here!"; exit 0; fi

# abort if the user is logged in
w | egrep -q '^#UID#'
if [ $? -eq 0 ]; then echo "Error: #UID# is logged in!"; exit 0; fi

# make sure the user id is not in use
for L in `getent passwd`; do
  C=`echo $L | awk 'BEGIN { FS=":" } { print $3 }'`
  if [ "$C" == "#UID_NUMBER#" ]; then
    echo "Error: UID Number '#UID_NUMBER#' is already in use!"
    echo $L
    exit 1
  fi
done

# get the original uid
OLDUID=`egrep '^#UID#:' /etc/passwd | awk 'BEGIN { FS=":" } { print $3 }'`
OLDGID=`egrep '^#UID#:' /etc/group | awk 'BEGIN { FS=":" } { print $3 }'`

# change the uid
usermod -u #UID_NUMBER# #UID#
if [ $? -ne 0 ]; then
  echo "Error changing uid";
  exit 1;
fi
echo "Changed UID for #UID# from $OLDUID to #UID_NUMBER#"

groupmod -g #UID_NUMBER# #UID#
if [ $? -ne 0 ]; then
  echo "Error changing gid";
  GROUPCONT=0
else
  GROUPCONT=1
  usermod -g #UID_NUMBER# #UID#
fi

# get the home directory
HOMED=`grep #UID# /etc/passwd | awk 'BEGIN { FS=":" } { print $6 }'`

# fixup ownership on the home directory
if [[ -d ${HOMED} && "${HOMED}" == "/home/#UID#" ]]; then
  chown -R #UID#. /home/#UID#
else
  echo "The home directory is not standard. Relying on find to fixup the permissions."
fi

# fixup ownership on everything else
for F in `find / -user $OLDUID 2>/dev/null | egrep -iv '^/(dev|proc)/'`; do chown #UID# $F; done
if [ $GROUPCONT -eq 1 ]; then
  for F in `find / -group $OLDGID 2>/dev/null | egrep -iv '^/(dev|proc)/'`; do chgrp #UID# $F; done
fi

echo 'successfully changed the UID for #UID#'
exit 0
