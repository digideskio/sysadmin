#!/bin/sh

# mysql-drop-user.sh
# drop a mysql user@host (or user at all hosts)
#
# William Strucke, wstrucke@gmail.com
# Version 1.0.0 2012-03-15
#
# can be run interactively or via lpad script
#

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

function usage {
  echo "Drop a MySQL user"
  echo
  echo "  Interactive Usage: user_id[@host]"
  echo
  echo "  Non-interactive Usage: Replace ## variables"
  echo
  exit 1
}

check_running

# local variables
HST=""
MYTEMPFILE=/tmp/mysql-drop-user.tmp.sql

# validate temp file
if [ -f $MYTEMPFILE ]; then rm -f $MYTEMPFILE; fi

# verify arguments and load settings
if [[ $# -ne 0 && $# -ne 1 ]]; then usage; fi
if [ $# -eq 1 ]; then
  # check whether or not the user id has a host
  echo $1 |grep -q '@'
  if [ $? -eq 0 ]; then
    SUSR=$( echo $1 |sed 's/\([^@]*\)@\(.*\)/\1/' )
    HST=$( echo $1 |sed 's/\([^@]*\)@\(.*\)/\2/' )
    SINGLE_HOST=1
  else
    SINGLE_HOST=0
    SUSR=$1
  fi
  INTERACTIVE=1
else
  SUSR="#USER_ID#"
  HST="#HOST#"
  # verify replacements have been made
  echo '#USER_ID# #HOST#' | egrep '^#.*#$' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Error: No arguments provided and substitution was not made."
    echo
    usage
  fi
  if [ "${HST}" == "" ]; then SINGLE_HOST=0; else SINGLE_HOST=1; fi
  INTERACTIVE=0
fi

# you must specify a user
if [ -z $SUSR ]; then echo "You didn't provide a user name. What are you trying to do here?"; exit 1; fi

# you may not drop root
echo $SUSR |grep -iq root
if [ $? -eq 0 ]; then echo "You want to drop root? Are you daft?"; exit 1; fi

# procedure
# - validate the input for special characters
# - validate the user ID by enumerating the hosts associated with it in mysql.user
# - if there are multiple hosts verify they all have the same password or throw an error
# - copy the account(s)
#

# validate the input for special characters
if [ "${SUSR//[^A-Za-z0-9-_\.]/}" != "$SUSR" ]; then
  echo "Error: Source user ID contained invalid characters!"
  exit 1
fi

# validate source account and password
if [ $SINGLE_HOST -eq 0 ]; then
  if [ `echo "SELECT User FROM user WHERE User='${SUSR}' LIMIT 1;" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'The source account does not exist'
    # its important that this has an exit status of zero when the account already does not exist due to the logic of other scripts
    exit 0
  fi
else
  if [ `echo "SELECT User FROM user WHERE User='${SUSR}' AND Host='${HST}';" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'The source account@host does not exist'
    # its important that this has an exit status of zero when the account already does not exist due to the logic of other scripts
    exit 0
  fi
fi

# get the server version
MYSQLVER=`echo "SHOW VARIABLES LIKE 'version';" | mysql -BN --skip-auto-rehash -o mysql | cut -f2`
echo $MYSQLVER | grep -Eq '^(5|6)\.'
if [ $? -ne 0 ]; then MYSQL4=1; else MYSQL4=0; fi

# the 'user' table MUST be the first the list due to the order the sql statements are compiled
if [ $MYSQL4 -eq 1 ]; then
  TABLES="user db columns_priv tables_priv"
else
  TABLES="user db columns_priv procs_priv tables_priv"
fi

echo "--------------------------------------------------------------------------------"
echo "Source Permissions:"; echo
if [ $SINGLE_HOST -eq 0 ]; then
  HOST_LIST=`echo "SELECT DISTINCT(Host) FROM user WHERE User='${SUSR}' ORDER BY Host;" | mysql -BN --skip-auto-rehash -o mysql`
  for H in $HOST_LIST; do
    echo "${H}:"
    echo "SHOW GRANTS FOR '${SUSR}'@'${H}';" | mysql -BN --skip-auto-rehash -o mysql
    echo
  done
else
  echo "SHOW GRANTS FOR '${SUSR}'@'${HST}';" | mysql -BN --skip-auto-rehash -o mysql
  echo
fi
echo
if [ $INTERACTIVE -eq 1 ]; then
  read -p "Is this the account you want to drop? Type yes to drop or anything else to abort: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted!"; exit 0; fi
fi

# copy the account
if [ $SINGLE_HOST -eq 0 ]; then
  WHERE="User='${SUSR}'"
else
  WHERE="User='${SUSR}' AND Host='${HST}'"
fi

# build the sql statements with backout
touch $MYTEMPFILE

# add backout statements
for TABLE in $TABLES; do
if [ $MYSQL4 -eq 1 ]; then
cat <<_EOF >>$MYTEMPFILE
DROP TABLE IF EXISTS backout_${TABLE};
CREATE TABLE backout_${TABLE} ENGINE=MYISAM SELECT * FROM ${TABLE};
_EOF
else
cat <<_EOF >>$MYTEMPFILE
DROP TABLE IF EXISTS backout_${TABLE};
CREATE TABLE backout_${TABLE} COMMENT 'backout table created `date +"%Y-%m-%d %H:%M:%S"` by $0 dropping ${SUSR}@${HST}' ENGINE MYISAM SELECT * FROM ${TABLE};
_EOF
fi
done
echo "" >>$MYTEMPFILE

# add drop user statements
for TABLE in $TABLES; do
  echo "DELETE FROM ${TABLE} WHERE ${WHERE};" >>$MYTEMPFILE
done

# execute
mysql -BN --skip-auto-rehash -o mysql < $MYTEMPFILE
if [ $? -ne 0 ]; then
  echo "There was an error running the SQL script @ ${MYTEMPFILE} - you may want to restore using the backout tables."
  echo "The new permissions HAVE NOT been applied yet but tables HAVE been updated. This is on you to fix things."
  echo
else
  echo "FLUSH PRIVILEGES;" | mysql -BN --skip-auto-rehash -o mysql
  echo "Successfully dropped user account"
  rm -f ${MYTEMPFILE}
fi

echo
exit
