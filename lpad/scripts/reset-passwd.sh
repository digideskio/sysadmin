#!/bin/bash

function apache_password {
  # requires $1 path to .htpasswd.users
  # requires $2 password hash
  # optional $3 (0|1) restart apache
  if [[ "$1" == "" || "$2" == "" ]]; then return 1; fi
  if [ ! -f $1 ]; then return 1; fi
  egrep -q '^#UID#:' $1 >/dev/null 2>&1
  if [ $? -ne 0 ]; then return 1; fi
  sed -i "s%#UID#:.*%#UID#:${2}%" $1
  if [[ $# -gt 2 && $3 -eq 1 ]]; then killall -USR1 httpd; elif [ $# -eq 2 ]; then killall -USR1 httpd; fi
  return 0
}

# verify replacement has been made
echo '#UID#' | egrep '^#.*#$' >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Error: Substitution not made. Do not run this script directly."
  exit 1
fi

# clear troublesome variables
unset CDPATH

# only continue if the account exists
egrep -q '^#UID#' /etc/passwd >/dev/null 2>&1
if [ $? -ne 0 ]; then exit 0; fi

# check OS version
cat /etc/*-release | grep 'release 6' >/dev/null 2>&1
if [ $? -eq 0 ]; then CENTOS=6; else CENTOS=5; fi

if [ $CENTOS -eq 6 ]; then
  usermod -p '#HASH6#' #UID#
else
  usermod -p '#HASH5#' #UID#
fi

chage -d `date +%F` #UID#

which pam_tally >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pam_tally --user #UID# --reset >/dev/null 2>&1
else
  pam_tally2 --user #UID# --reset >/dev/null 2>&1
fi

# handle special services
case "`hostname`" in
  example)
    apache_password /var/web/.htpasswd.users '#PSHA#'
    ;;
esac

echo 'successfully reset password for #UID#'
