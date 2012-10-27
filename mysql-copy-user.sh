#!/bin/sh

# mysql-copy-user.sh
# copy a mysql user@host (or user at all hosts) with identical permissions
#
# William Strucke, wstrucke@gmail.com
# Version 1.0.0 2012-02-05
#
# can be run interactively or via lpad script
#
# Copyright 2012                                                                
#                                                                               
# This program is free software: you can redistribute it and/or modify          
# it under the terms of the GNU General Public License as published by          
# the Free Software Foundation, either version 3 of the License, or             
# (at your option) any later version.                                           
#                                                                               
# This program is distributed in the hope that it will be useful,               
# but WITHOUT ANY WARRANTY; without even the implied warranty of                
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                 
# GNU General Public License for more details.                                  
#                                                                               
# You should have received a copy of the GNU General Public License             
# along with this program.  If not, see <http://www.gnu.org/licenses/>.         
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
  echo "Copy a MySQL user to a new account with identical permissions"
  echo
  echo "  Interactive Usage: source_id [source_host] destination_id [destination_host] hash"
  echo
  echo "  Non-interactive Usage: Replace ## variables"
  echo
  exit 1
}

check_running

# local variables
MYTEMPFILE=/tmp/mysql-copy-user.tmp.sql

# validate temp file
if [ -f $MYTEMPFILE ]; then rm -f $MYTEMPFILE; fi

# verify arguments and load settings
if [[ $# -ne 0 && $# -ne 3 && $# -ne 5 ]]; then usage; fi
if [ $# -eq 3 ]; then
  SUSR=$1
  DUSR=$2
  DPASS=$3
  SINGLE_HOST=0
  INTERACTIVE=1
elif [ $# -eq 5 ]; then
  SUSR=$1
  SHST=$2
  DUSR=$3
  DHST=$4
  DPASS=$5
  SINGLE_HOST=1
  INTERACTIVE=1
else
  SUSR="#SOURCE_UID#"
  SHST="#SOURCE_HOST#"
  DUSR="#DEST_UID#"
  DHST="#DEST_HOST#"
  DPASS="#HASH#"
  # verify replacements have been made
  echo '#SOURCE_UID# #DEST_UID# #HASH#' | egrep '^#.*#$' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Error: No arguments provided and substitution was not made."
    echo
    usage
  fi
  if [[ "${SHST}" == "" || "${DHST}" == "" ]]; then SINGLE_HOST=0; else SINGLE_HOST=1; fi
  INTERACTIVE=0
fi

# procedure
# - validate the input for special characters
# - validate the user ID by enumerating the hosts associated with it in mysql.user
# - if there are multiple hosts verify they all have the same password or throw an error
# - copy the account(s)
#

# validate the input for special characters
if [[ "${SUSR//[^A-Za-z0-9-_\.]/}" != "$SUSR" || "${DUSR//[^A-Za-z0-9-_\.]/}" != "$DUSR" ]]; then
  echo "Error: Source or Destination user ID contained invalid characters!"
  exit 1
fi
if [ "${DPASS}" != "${DPASS//[^A-Za-z0-9\*]/}" ]; then
  echo "Error: Password hash contained invalid characters!"
  exit 1
fi

# validate source account and password
if [ $SINGLE_HOST -eq 0 ]; then
  if [ `echo "SELECT User FROM user WHERE User='${SUSR}' GROUP BY Password;" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'Error: Source account does not exist or has multiple passwords'
    exit 1
  fi
else
  if [ `echo "SELECT User FROM user WHERE User='${SUSR}' AND Host='${SHST}';" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 1 ]; then
    echo 'Error: Source account@host does not exist'
    exit 1
  fi
fi

# validate destination account and password
if [ $SINGLE_HOST -eq 0 ]; then
  # copying all hosts, verify this is a brand new user id
  if [ `echo "SELECT User FROM user WHERE User='${DUSR}';" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 0 ]; then
    echo 'Error: destination account already exists, please copy manually or select a new ID'
    exit 1
  fi
else
  # copying one host, verify this host/user combination is new
  if [ `echo "SELECT User FROM user WHERE User='${DUSR}' AND Host='${DHST}'" | mysql -BN --skip-auto-rehash -o mysql | wc -l` -ne 0 ]; then
    echo 'Error: destination account@host already exists, please select a new ID and/or Host to copy to'
    exit 1
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
  echo "SHOW GRANTS FOR '${SUSR}'@'${SHST}';" | mysql -BN --skip-auto-rehash -o mysql
  echo
fi
echo
if [ $INTERACTIVE -eq 1 ]; then
  read -p "Are the source permissions accurate? Type yes to copy or anything else to abort: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then echo "Aborted!"; exit 0; fi
fi

# copy the account
if [ $SINGLE_HOST -eq 0 ]; then
  WHERE="WHERE User='${SUSR}'"
  UPDATE="SET User='${DUSR}', Password='${DPASS}'"
  UPDATE_ALL="SET User='${DUSR}'"
else
  WHERE="WHERE User='${SUSR}' AND Host='${SHST}'"
  UPDATE="SET User='${DUSR}', Host='${DHST}', Password='${DPASS}'"
  UPDATE_ALL="SET User='${DUSR}', Host='${DHST}'"
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
CREATE TABLE backout_${TABLE} COMMENT 'backout table created `date +"%Y-%m-%d %H:%M:%S"` by $0 copying ${SUSR}@${SHST} to ${DUSR}@${DHST}' ENGINE MYISAM SELECT * FROM ${TABLE};
_EOF
fi
done
echo "" >>$MYTEMPFILE

# add copy user statements
for TABLE in $TABLES; do
cat <<_EOF >>$MYTEMPFILE
CREATE TEMPORARY TABLE temp_copy_${TABLE} SELECT * FROM ${TABLE} ${WHERE};
UPDATE temp_copy_${TABLE} ${UPDATE};
INSERT INTO ${TABLE} SELECT * FROM temp_copy_${TABLE};
DROP TABLE temp_copy_${TABLE};

_EOF
UPDATE="$UPDATE_ALL"
done

# execute
mysql -BN --skip-auto-rehash -o mysql < $MYTEMPFILE
if [ $? -ne 0 ]; then
  echo "There was an error running the SQL script @ ${MYTEMPFILE} - you may want to restore using the backout tables."
  echo "The new permissions HAVE NOT been applied yet but tables HAVE been updated. This is on you to fix things."
  echo
else
  echo "FLUSH PRIVILEGES;" | mysql -BN --skip-auto-rehash -o mysql
  rm -f ${MYTEMPFILE}
fi

# display the new permissions
echo "--------------------------------------------------------------------------------"
echo "New permissions:"; echo
if [ $SINGLE_HOST -eq 0 ]; then
  HOST_LIST=`echo "SELECT DISTINCT(Host) FROM user WHERE User='${DUSR}' ORDER BY Host;" | mysql -BN --skip-auto-rehash -o mysql`
  for H in $HOST_LIST; do
    echo "${H}:"
    echo "SHOW GRANTS FOR '${DUSR}'@'${H}';" | mysql -BN --skip-auto-rehash -o mysql
    echo
  done
else
  echo "${DHST}:"
  echo "SHOW GRANTS FOR '${DUSR}'@'${DHST}';" | mysql -BN --skip-auto-rehash -o mysql
  echo
fi

echo
exit
