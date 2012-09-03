#!/bin/sh

# add a user to the system by copying permissions
#   from another, existing account
#
# requires:
#   #SOURCE#        source user (to copy from)
#   #UID#           new user id
#   #DESC#          new user description
#   #UID_NUMBER#    new user id number
#   #HASH5#         centos 5 compatible password hash
#   #HASH6#         centos 6 compatibile password hash
#   #PSHA#          apache sha password
#   #PCRYPT#        apache crypt password
#
# much of this functionality will fail if a new user id is a substring of an existing ID!
#

function apache_password {
  # requires $1 path to .htpasswd.users
  # requires $2 password hash
  # optional $3 (0|1) restart apache
  if [[ "$1" == "" || "$2" == "" ]]; then return 1; fi
  if [ ! -f $1 ]; then return 1; fi
  # make sure the source account exists
  egrep -q '^#SOURCE#:' $1 >/dev/null 2>&1
  if [ $? -ne 0 ]; then return 0; fi
  # reset the password if the new account exists
  egrep -q '^#UID#:' $1 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    # add the account
    echo "#UID#:${2}" >> $1
    echo 'Added to apache'
  else
    # reset the password
    sed -i "s%#UID#:.*%#UID#:${2}%" $1
    echo 'Reset apache password'
  fi
  if [[ $# -gt 2 && $3 -eq 1 ]]; then killall -USR1 httpd; elif [ $# -eq 2 ]; then killall -USR1 httpd; fi
  return 0
}

function nagios_permissions {
  # requires $1 path to cgi.cfg
  if [ "$1" == "" ]; then return 1; fi
  if [ ! -f $1 ]; then return 1; fi
  # make sure the source account exists
  egrep -q '#SOURCE#' $1 >/dev/null 2>&1
  if [ $? -ne 0 ]; then return 0; fi
  # make sure the new account does not exist
  egrep -q '#UID#' $1 >/dev/null 2>&1
  if [ $? -eq 0 ]; then echo "Account matched in nagios ${1}, aborting..."; return 1; fi
  # add the new account
  # ... this gets complicated since we have to account for the source being the last item in the list or not
  return 1
  
  # sed -i.ws 's%#SOURCE#%#SOURCE#,#UID#%' $1
  # diff $1{.ws,}

  # nagios verification
  /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg >/dev/null 2>&1
  if [ $? -ne 0 ]; then echo "Nagios configuration error, please verify manually!"; return 1; fi
  # reload
  /etc/init.d/nagios reload >/dev/null 2>&1
  if [ $? -ne 0 ]; then echo "Error reloading nagios! Please fix immediately!"; return 1; fi
  echo "Nagios permissions updated"
  return 0
}

# verify replacement has been made
echo '#SOURCE# #UID# #UID_NUMBER#' | egrep '^#.*#$' >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Error: Substitution not made. Do not run this script directly."
  exit 1
fi

# clear troublesome variables
unset CDPATH

# only continue if the source account exists
egrep -q '^#SOURCE#' /etc/passwd >/dev/null 2>&1
if [ $? -ne 0 ]; then exit 0; fi

# check OS version
cat /etc/*-release | grep 'release 6' >/dev/null 2>&1
if [ $? -eq 0 ]; then CENTOS=6; else CENTOS=5; fi

# test for and add the account as needed
egrep -q '^#UID#:' /etc/passwd >/dev/null 2>&1
if [ $? -eq 1 ]; then
  # make sure the user id is not in use
  getent passwd | grep ':#UID_NUMBER#:' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Error: UID Number '#UID_NUMBER#' is already in use!"
    exit 1
  fi
  # add the new account
  useradd -u #UID_NUMBER# -c "#DESC#" #UID#
  if [ $? -ne 0 ]; then
    echo "Error adding account";
    exit 1;
  fi
  echo "Added account: #UID#"
else
  echo "Account already exists, verifying permissions"
fi

# set or reset the password
if [ $CENTOS -eq 6 ]; then
  usermod -p '#HASH6#' #UID#
else
  usermod -p '#HASH5#' #UID#
fi

# ensure the account is unlocked (for existing accounts)
which pam_tally >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pam_tally --user #UID# --reset >/dev/null 2>&1
else
  pam_tally2 --user #UID# --reset >/dev/null 2>&1
fi

# test the uid number
egrep '^#UID#:' /etc/passwd | grep -q ':#UID_NUMBER#:' >/dev/null 2>&1
if [ $? -ne 0 ]; then echo "Warning: #UID# has the wrong ID number"; fi

# copy the group membership (excluding the user's default group)
for G in `grep #SOURCE# /etc/group | egrep -v '^#SOURCE#:' | awk 'BEGIN { FS=":" } { print $1 }'`; do
  egrep "^${G}:" /etc/group | grep -q #UID# >/dev/null 2>&1
  if [ $? -eq 1 ]; then gpasswd -a #UID# ${G}; fi
  echo "Added to group: ${G}"
done 

# check sudoers
egrep '^User_Alias' /etc/sudoers | grep -q #SOURCE# >/dev/null 2>&1
if [ $? -eq 0 ]; then
  egrep '^User_Alias' /etc/sudoers | grep -q #UID# >/dev/null 2>&1
  if [ $? -eq 1 ]; then
    sed -i.ws 's%#SOURCE#%#SOURCE#,#UID#%' /etc/sudoers
    echo "Added to sudoers"
  fi
fi

# check access.conf
grep '#SOURCE#' /etc/security/access.conf >/dev/null 2>&1
if [ $? -eq 0 ]; then
  grep '#UID#' /etc/security/access.conf >/dev/null 2>&1
  if [ $? -eq 1 ]; then
    sed -i.ws 's%#SOURCE#%#SOURCE# #UID#%' /etc/security/access.conf
    echo "Added to PAM Access"
  fi
fi

# handle special services
case "`hostname`" in
  example)
    apache_password /var/web/.htpasswd.users '#PSHA#'
    ;;
esac

echo 'successfully added or copied #UID#'
