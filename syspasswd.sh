#!/bin/sh

# generate linux system passwords from stdin
# w. strucke 2011-12-07
#
# Copyright 2011
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
# in order to properly set the netscreen credential, please provide the
#  USERID environment variable to this script, otherwise the userid will
#  be set to "netscreen"
#
# returns ten variables:
#  $PMD5          md5 system password
#  $PSHA512       sha-512 system password
#  $PMYSQL        mysql 4.1 password
#  $PMYSQL_OLD    mysql 3.2.3 password
#  $PCRYPT        apache crypt password
#  $PSHA          apache sha password
#  $PMD5_BASIC    simple md5 encryption (cactii)
#  $PMD5_CISCO    simple md5 encryption (cisco ios)
#  $PSHA_SIMPLE   simple SHA1 encoded password
#  $PSCREENOS     screenos salted hash
#

DEBUG=0

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

# this was generated from Jack The Ripper
# source: http://openwall.info/wiki/john/Generating-test-hashes
#  functions "ns" and "ns_base64_2"
# retrieved: 2013-01-22 ws
#
netscreen() {
  test $# -lt 2 && return
  P=${@:2}
  perl -e "use Digest::MD5 qw(md5 md5_hex md5_base64);\
my \$h = md5(q($1:Administration Tools:$P));\
my @ns_i64 = ('A'..'Z', 'a'..'z','0'..'9','+','/',);\
my \$i; my \$hh = \"\"; my \$n; my @ha = split(//,\$h);\
for (\$i = 0; \$i < 8; ++\$i) {\
        \$n = ord(\$ha[\$i*2])<<8;\
        if (@ha > \$i*2+1) { \$n |= ord(\$ha[\$i*2+1]); }\
        \$hh .= \"\$ns_i64[(\$n>>12)&0xF]\";\
        \$hh .= \"\$ns_i64[(\$n>>6)&0x3F]\";\
        \$hh .= \"\$ns_i64[\$n&0x3F]\";\
};\
substr(\$hh, 0, 0) = 'n';\
substr(\$hh, 6, 0) = 'r';\
substr(\$hh, 12, 0) = 'c';\
substr(\$hh, 17, 0) = 's';\
substr(\$hh, 23, 0) = 't';\
substr(\$hh, 29, 0) = 'n';\
print \"\$hh\\n\";"
}

nspsk() {
  test $# -lt 2 && return
  P=${@:2}
  perl -e "use Digest::MD5 qw(md5 md5_hex md5_base64);\
my \$h = md5(q($1:Administration Tools:$P));\
print \"\$h\\n\";"
}

# argument handling
while [ $# -gt 0 ]; do case "$1" in
  --debug) DEBUG=1;;
esac; shift; done

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

# get the openssl version
if [[ "`openssl version 2>&1`" =~ ^OpenSSL\ 1.* ]]; then OPENSSLV1=1; else OPENSSLV1=0; fi

# possibly do password strength verification here
#  minimum length
#  minimum characters
#  dictionary check
#
# possibly based on dest system type (-dev -prod etc...)
#

# escape shell command characters
#PASS=`echo ${PASS} | sed -re 's/(["$\`])/\\\\\\1/g'`
QPASS=$( printf -- $PASS |sed 's/"/\\"/g' )

# generate the password
if [ $OPENSSLV1 -eq 0 ]; then
  export PMYSQL="*`echo -n "${PASS}" | openssl dgst -sha1 -binary | openssl dgst -sha1 | tr '[:lower:]' '[:upper:]'`"
else
  export PMYSQL="*`echo -n "${PASS}" | openssl dgst -sha1 -binary | openssl dgst -sha1 | tr '[:lower:]' '[:upper:]' | awk '{print $2}'`"
fi

# generate the password
export PMYSQL_OLD=$(mysql323 "${PASS}")

# generate the password
export PCRYPT=`printf -- "${PASS}" | openssl passwd -crypt -stdin`

# generate the password
export PSHA="{SHA}`printf -- "${PASS}" | openssl dgst -sha1 -binary | openssl enc -base64`"

# generate the password
if [ $OPENSSLV1 -eq 0 ]; then
  export PSHA_SIMPLE="`printf -- "${PASS}" | openssl dgst -sha1 | tr 'a-z' 'A-Z'`"
else
  export PSHA_SIMPLE="`printf -- "${PASS}" | openssl dgst -sha1 | tr 'a-z' 'A-Z' | awk '{print $2}'`"
fi

# generate the password
export PMD5_BASIC=`printf -- "${PASS}" | md5sum - | awk '{ print $1 }'`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c8`
export PMD5=`printf -- "${PASS}" | openssl passwd -1 -salt ${SALT} -stdin`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c8`
export PSHA512=`python -c "import crypt, getpass, pwd; print crypt.crypt(\"${QPASS}\", '\\\$6\\\$${SALT}\\\$')"`

# generate a random salt and the password
SALT=`< /dev/urandom tr -dc A-Za-z0-9-._ | head -c4`
export PMD5_CISCO=`printf -- "${PASS}" | openssl passwd -1 -salt ${SALT} -stdin`

# generate password using perl
test -z ${USERID} && USERID=netscreen
export PSCREENOS="$(netscreen ${USERID} ${PASS})"

if [ $DEBUG -eq 1 ]; then
  printf -- "PASS: ${PASS}\n" >&2
  echo "MYSQL: ${PMYSQL}" >&2
  echo "MYSQL_OLD: ${PMYSQL_OLD}" >&2
  echo "System MD5: ${PMD5}" >&2
  echo "System SHA-512: ${PSHA512}" >&2
  echo "CRYPT: ${PCRYPT}" >&2
  echo "Apache SHA: ${PSHA}" >&2
  echo "Simple SHA1: ${PSHA_SIMPLE}" >&2
  echo "Basic MD5: ${PMD5_BASIC}" >&2
  echo "Cisco MD5: ${PMD5_CISCO}" >&2
  echo "ScreenOS: ${PSCREENOS}" >&2
  nspsk ${USERID} ${PASS} |openssl base64 >&2
fi

unset SALT
