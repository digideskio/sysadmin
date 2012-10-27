#!/bin/sh

# generate linux system passwords from stdin
#
# w. strucke 2011-12-07
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
# returns nine variables:
#  $PMD5          md5 system password
#  $PSHA512       sha-512 system password
#  $PMYSQL        mysql 4.1+ password
#  $PMYSQL_OLD    mysql 3.2.3 password
#  $PCRYPT        apache crypt password
#  $PSHA          apache sha password
#  $PMD5_BASIC    simple md5 encryption (cacti)
#  $PMD5_CISCO    simple md5 encryption (cisco ios)
#  $PSHA_SIMPLE   simple SHA1 encoded password
#

chr() { printf \\$(printf '%03o' $1); }
ord() { printf '%d' "'$1"; }

mysql323() {
  nr=0x50305735
  nr2=0x12345671
  add=7
  PASS="$1"
  for ((i=0;i<${#PASS};i++)); do
    if [[ "${PASS:$i:1}" == " " || "${PASS:$i:1}" == "\t" || "${PASS:$i:1}" == "" ]]; then continue; fi
    CH=$( ord ${PASS:$i:1} );
    nr=$(( $nr ^ ((($nr & 63) + $add) * $CH) + ($nr << 8) ));
    nr=$(( $nr & 0x7fffffff ))
    nr2=$(( $nr2 + (($nr2 << 8) ^ $nr) ))
    nr2=$(( $nr2 & 0x7fffffff ))
    add=$(( $add + $CH ))
  done
  out_a=$(($nr & 0x7fffffff));
  out_b=$(($nr2 & 0x7fffffff));
  printf "%08x%08x" $out_a $out_b;
}

# allow this script to be sourced with an initial password
if [ -z "$PASS" ]; then
  echo -n "Password: "
  read -s PASS
  echo
  echo -n "Confirm: "
  read -s CONFIRM
  echo
  if [[ "$PASS" != "$CONFIRM" || "$PASS" == "" ]]; then
    echo "Invalid or empty password provided!"
    exit 1
  fi
fi

# possibly do password strength verification here
#  minimum length
#  minimum characters
#  dictionary check
#
# possibly based on dest system type (-dev -prod etc...)
#

# escape shell command characters
#PASS=`echo ${PASS} | sed -re 's/(["$\`])/\\\\\\1/g'`

# generate the password
export PMYSQL="*`echo -n "${PASS}" | openssl dgst -sha1 -binary | openssl dgst -sha1 | tr '[:lower:]' '[:upper:]'`"

# generate the password
export PMYSQL_OLD=$(mysql323 "${PASS}")

# generate the password
export PCRYPT=`echo -n "${PASS}" | openssl passwd -crypt -stdin`

# generate the password
export PSHA="{SHA}`echo -n "${PASS}" | openssl dgst -sha1 -binary | openssl enc -base64`"

# generate the password
export PSHA_SIMPLE="`echo -n "${PASS}" | openssl dgst -sha1 | tr 'a-z' 'A-Z'`"

# generate the password
export PMD5_BASIC=`echo -n "${PASS}" | md5sum - | awk '{ print $1 }'`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c8`
export PMD5=`echo -n "${PASS}" | openssl passwd -1 -salt ${SALT} -stdin`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c8`
export PSHA512=`python -c "import crypt, getpass, pwd; print crypt.crypt(\"${PASS}\", '\\\$6\\\$${SALT}\\\$')"`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c4`
export PMD5_CISCO=`echo -n "${PASS}" | openssl passwd -1 -salt ${SALT} -stdin`

#echo "PASS: ${PASS}"
#echo "MYSQL: ${PMYSQL}"
#echo "MYSQL_OLD: ${PMYSQL_OLD}"
#echo "System MD5: ${PMD5}"
#echo "System SHA-512: ${PSHA512}"
#echo "CRYPT: ${PCRYPT}"
#echo "Apache SHA: ${PSHA}"
#echo "Simple SHA1: ${PSHA_SIMPLE}"
#echo "Basic MD5: ${PMD5_BASIC}"
#echo "Cisco MD5: ${PMD5_CISCO}"

unset SALT
