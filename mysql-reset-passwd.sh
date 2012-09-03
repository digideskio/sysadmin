#!/bin/sh

# mysql-reset-passwd.sh
# reset a mysql password for user@host (or user at all hosts) without changing permissions
#
# William Strucke, wstrucke@gmail.com
# Version 1.0.0, 2012-03-06
#
# can be run interactively or via lpad script
#
# will correctly handle root password changes, including restarting SQLKiller.pl
#   and updating /root/.my.cnf as needed
#

function check_root {
  # if the user was root, update the my.cnf
  if [[ "${USR}" == "root" && -f /root/.my.cnf ]]; then
    echo; echo "Updating root my.cnf..."
    sed -i.tmp 's/password=.*/password='${PASS}'/' /root/.my.cnf
    sed -i 's/pass=.*/pass='${PASS}'/' /root/.my.cnf
    diff /root/.my.cnf{.tmp,}
    rm -f /root/.my.cnf.tmp
  fi
}

function check_running {
  alias exit='if [ -f $LOCK ]; then rm -f $LOCK; fi; exit'
  LOCK=".`basename $0`.lck"
  test -f $LOCK && PID=`cat $LOCK 2>/dev/null` || PID=""
  if [[ -f $LOCK && `ps h -p $PID |wc -l` -ne 0 ]]; then
    echo "`basename $0` is already running [$PID]"
    exit 1
  else
    echo $$ >$LOCK
  fi
}

function check_service {
  # tell daemontools to restart sqlkiller if it exists
  if [ -d /service/SQLKiller ]; then
    echo; echo "Restarting SQLKiller..."
    /command/svc -d /service/SQLKiller
    /command/svc -u /service/clear
    /command/svc -u /service/SQLKiller
  fi
}

function usage {
  echo "Reset a MySQL user's password without changing permissions"
  echo
  echo "  Interactive Usage: --user user_id [--host hostname_or_ip] [--skip-db]"
  echo "    - You will be prompted for the new password"
  echo
  echo "  Non-interactive Usage: Replace ## variables"
  echo
  exit 1
}

check_running

# local settings
MYTEMPFILE=/tmp/mysql-reset-passwd.tmp.sql
SYSPASSWD=../../syspasswd.sh

# initialize variables
INTERACTIVE=1
PASS=""
PHASH=""
SKIPDB=0
SINGLE_HOST=0
USR=""

# validate temp file
if [ -f $MYTEMPFILE ]; then rm -f $MYTEMPFILE; fi

# process arguments
if [ $# -eq 0 ]; then
  # non-interactive run
  HST="#HOST#"
  PASS="#PASSWD#"
  PHASH="#HASH#"
  SKIPDB="#SKIPDB#"
  USR="#UID#"
  # verify replacements have been made
  echo '#UID# #PHASH# #SKIPDB#' |grep -qE '^#.*#$'
  if [ $? -eq 0 ]; then
    echo "Error: No arguments provided and substitution was not made."
    echo
    usage
  fi
  [ "${HST}" != "" ] && SINGLE_HOST=1
  [ "$SKIPDB" == "1" ] && SKIPDB=1 || SKIPDB=0
  INTERACTIVE=0
else
  while [ $1 ]; do case $1 in
    --user) USR=$2; shift;;
    --host) HST=$2; SINGLE_HOST=1; shift;;
    --skip-db) SKIPDB=1;;
    *) usage;;
  esac; shift; done
fi

# get the password as needed
if [ $INTERACTIVE -eq 1 ]; then
  source $SYSPASSWD
  if [ "`hostname`" == "db-01" ]; then PHASH=${PMYSQL_OLD}; else PHASH=${PMYSQL}; fi
fi

# make sure the password is sane
echo -n $PHASH |grep -qE '^\*[A-Z0-9]{40}$'
if [ $? -ne 0 ]; then
  echo -n $PHASH |grep -qE '^[a-z0-9]{16}$'
  if [ $? -ne 0 ]; then
    # invalid hash!
    echo "Error: The hash provided was invalid!"; exit 1
  fi
fi

# final validation
if [[ "$USR" == "root" && "$PASS" == "" ]]; then
  echo "Error: PASS is required to reset the root password!"
  exit 1
fi

# procedure
# - validate the input for special characters
# - validate the user ID by enumerating the hosts associated with it in mysql.user
# - if there are multiple hosts verify they all have the same password or throw an error
# - reset the password
#

if [ $SKIPDB -eq 1 ]; then
  echo "Skipping database updates for slave server..."
  check_root
  check_service
  echo
  exit 0
fi

# validate the input for special characters
if [ "${USR//[^A-Za-z0-9-_\.]/}" != "$USR" ]; then
  echo "Error: User ID contained invalid characters!"
  exit 1
fi
if [ "${PASS}" != "${PASS//[^A-Za-z0-9-_\.\$\';\*]/}" ]; then
  echo "Error: Password hash contained invalid characters!"
  exit 1
fi

# validate source account and password
if [ $SINGLE_HOST -eq 0 ]; then
  if [ `echo "SELECT User FROM user WHERE User='${USR}' GROUP BY Password;" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'Error: Source account does not exist or has multiple passwords'
    exit 1
  fi
else
  if [ `echo "SELECT User FROM user WHERE User='${USR}' AND Host='${HST}';" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'Error: Source account@host does not exist'
    exit 1
  fi
fi

# get the server version
MYSQLVER=`echo "SHOW VARIABLES LIKE 'version';" | mysql -BN --skip-auto-rehash -o mysql | cut -f2`
echo $MYSQLVER | grep -Eq '^(5|6)\.'
if [ $? -ne 0 ]; then MYSQL4=1; else MYSQL4=0; fi

# update the password
if [ $SINGLE_HOST -eq 0 ]; then
  WHERE="WHERE User='${USR}'"
else
  WHERE="WHERE User='${USR}' AND Host='${HST}'"
fi

# build the sql statements with backout
touch $MYTEMPFILE

# add backout statements
if [ $MYSQL4 -eq 1 ]; then
cat <<_EOF >>$MYTEMPFILE
DROP TABLE IF EXISTS backout_user;
CREATE TABLE backout_user ENGINE=MYISAM SELECT * FROM user;
_EOF
else
cat <<_EOF >>$MYTEMPFILE
DROP TABLE IF EXISTS backout_user;
CREATE TABLE backout_user COMMENT 'backout table created `date +"%Y-%m-%d %H:%M:%S"` by $0 resetting password for ${USR}@${HST}' ENGINE MYISAM SELECT * FROM user;
_EOF
fi
echo "" >>$MYTEMPFILE

# add reset password statements
echo "UPDATE user SET Password='${PHASH}' ${WHERE};" >>${MYTEMPFILE}

# execute
mysql -BN --skip-auto-rehash -o mysql < ${MYTEMPFILE}
if [ $? -ne 0 ]; then
  echo "There was an error running the SQL script @ ${MYTEMPFILE} - you may want to restore using the backout tables."
  echo "The new permissions HAVE NOT been applied yet but tables HAVE been updated. This is on you to fix things."
  echo
else
  echo "Successfully reset MySQL password for ${USR}"
  echo "FLUSH PRIVILEGES;" | mysql -BN --skip-auto-rehash -o mysql
  rm -f ${MYTEMPFILE}
fi

check_root
check_service

echo
exit 0
