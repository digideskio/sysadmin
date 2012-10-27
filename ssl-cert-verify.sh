#!/bin/bash

# retrieve ssl certificate chain from a web site or local file,
# extract, validate, and enumerate every certificate
#
# version 1.0.0, wstrucke
# oct-11-2011
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

function TOERR {
  # error, cleanup and exit
  echo "Error processing certificates"
  rm -f tmp.crt parta00 parta01 partb00 partb01
  exit -1
}

function usage {
  # output usage and exit
  echo "Usage:
  $0 command path (options)

  Commands:
    -d|--download   Download a certificate from a server. Requires the server address and port
                      in the form of 'sample.com:443'
    -f|--file       Check an existing file. Requires the path to the file

  Options:
    -m|--match      Filter output and only display results matching the provided expression
"
  exit 0
}

# initialize defaults
DOWNLOAD=0
FILE=0
COUNT=0
MATCH=0
MATCHCOUNT=0
MATCHLIST=""

# get args
while [ $1 ]; do case "$1" in
  --download|-d)
    # download a cert to check
    DOWNLOAD=1
    SRC="$2"
    shift;
    ;;
  --file|-f)
    # check a file
    FILE=1
    SRC="$2"
    shift;
    ;;
  --match|-m)
    # filter the output
    MATCH=1
    FILTER="$2"
    shift;
    ;;
  *) usage;;
esac; shift; done

# verify input
if [[ ${DOWNLOAD} -eq 0 && ${FILE} -eq 0 ]]; then usage; fi

# this script dumps a lot of crap in the current folder
echo "WARNING: this script dumps a lot of crap in your current directory. We strongly
  encourage you to create a new, empty sub-directory and run this script from there.

Current path: `pwd`
"
echo -n "Type 'yes' to confirm you really want to run this script here or 'create'
  and I will make a folder for you (ssl-cert-verify-tmp): "
read ROLECONFIRM
echo
echo
if [ "$ROLECONFIRM" == "create" ]; then
  mkdir ssl-cert-verify-tmp
  cd ssl-cert-verify-tmp
  ROLECONFIRM="yes"
fi
if [ "$ROLECONFIRM" != "yes" ]; then echo "Aborted!"; exit 0; fi

# intro
echo "********************************************************************************"
echo "Processing SSL Certificates for ${SRC}"
if [[ ${DOWNLOAD} -eq 1 ]]; then echo "++ Mode: Download"; else echo "++ Mode: Local File"; fi
if [[ ${MATCH} -eq 1 ]]; then echo "++ Using filter match: '${FILTER}'"; fi
echo

# collect the certificate(s) and create tmp.crt to process
if [[ ${DOWNLOAD} -eq 1 ]]; then
  # download the certificate bundle
  openssl s_client -showcerts -connect ${SRC} </dev/null >tmp.crt 2>/dev/null
  if [ $? -ne 0 ]; then TOERR; fi
elif [[ ${FILE} -eq 1 ]]; then
  /bin/cp ${SRC} tmp.crt
  SRC=`basename ${SRC}`
fi

echo "Basic Verification - Certificate Bundle"
S=`openssl verify -verbose tmp.crt 2>/dev/null | grep -v 'OK'`
if [[ "${S}" != "" ]]; then
  echo ${S} |grep 'unable to get local issuer certificate' >/dev/null 2>&1
  test $? -eq 0 && echo "-- tmp.crt: Error: Missing or incomplete CA chain" || echo "-- ${S}"
else echo "++ tmp.crt: OK"; fi

# extract the "host" from the provided address or file path
HOST=`echo ${SRC} | cut -d':' -f1`

# extract the certs
csplit -szf parta tmp.crt '/-----BEGIN CERTIFICATE-----/' {1} >/dev/null 2>&1
while [ $? -eq 0 ]; do
  grep -qe '-----BEGIN CERTIFICATE-----' parta00
  if [[ $? -ne 0 ]]; then
    rm -f parta00
        mv parta01 parta00
        mv parta02 parta01
  fi
  grep -qe '-----END CERTIFICATE-----' parta00
  if [[ $? -ne 0 ]]; then echo '-----END CERTIFICATE-----' >> parta00; fi
  cat parta00 >> ${HOST}-${COUNT}.crt
  rm -f parta00 partb00 partb01
  mv parta01 partb01
  COUNT=$(( ${COUNT}+1 ))
  csplit -szf parta partb01 '/-----BEGIN CERTIFICATE-----/' {1} >/dev/null 2>&1
done
# handle the last cert
if [ ! -f partb01 ]; then cp tmp.crt partb01; fi
csplit -szf parta partb01 '/-----BEGIN CERTIFICATE-----/' {0} >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  cat parta00 >> ${HOST}-${COUNT}.crt
  COUNT=$(( ${COUNT}+1 ))
fi
rm -f parta00 partb00 partb01 tmp.crt

# verify extraction
if [[ ${COUNT} -eq 0 ]]; then
  echo "There are no certificates to process."
  exit 0
fi

# status update
echo -ne "\nSuccessfully extracted ${COUNT} certificates\n\n"

# basic verification
echo "Basic Verification - Component Certificates"
OK=0
OK_CERTS=()
NOTOK_COUNT=0
NOTOK_CERTS=()
for (( i=0; i<${COUNT}; i++ )); do
  S=`openssl verify -verbose ${HOST}-${i}.crt 2>/dev/null | grep -v 'OK'`
  if [[ ${MATCH} -eq 1 && "`echo \"$S\" | grep -ie ${FILTER}`" == "" ]]; then continue; fi
  if [[ "${S}" != "" ]]; then
    echo ${S} |grep 'unable to get local issuer certificate' >/dev/null 2>&1
    test $? -eq 0 && echo "-- ${HOST}-${i}.crt: Error: Missing or incomplete CA chain" || echo "-- ${S}"
    NOTOK_COUNT=$((${NOTOK_COUNT}+1))
    NOTOK_CERTS[${#NOTOK_CERTS[@]}]="${HOST}-${i}.crt"
  else
    echo "++ ${HOST}-${i}.crt: OK"
    OK=1
    OK_CERTS[${#OK_CERTS[@]}]="${HOST}-${i}.crt"
  fi
done
echo

# advanced verification
if [ $OK -eq 0 ]; then
  #echo "********************************************************************************"
  echo -ne "No certificates could be validated against the system CA bundle.  This likely
indicates the issuer is using a self-signed certificate or an incomplete or
missing certificate chain. If a chain was provided it's possible the root CA is
new enough that our system bundle does not have it installed, in which case we
should fix that.\n\n"
elif [ $NOTOK_COUNT -gt 0 ]; then
  echo -ne "One or more certificates in the chain validated but at least one did not.
OpenSSL does not look at every certificate in the chain during basic
verification so we're going to extract the certificate or certificates that did
not verify and analyze them against a custom CA bundle including the system
bundle combined with the provided certificates that did validate in order to
attempt to establish a proper CA chain using the verified certificates.\n
If this comes out ok then it's very likely a valid certificate chain has been
presented by the server.  Obviusly this is highly context dependent so you
should check the certs manually if you have any doubts.\n\n"
#********************************************************************************
  echo "Advanced Verification - Using Provided CA Chain"
  # as the explanation says, concat the OK certs with the system bundle
  SYSTEM_BUNDLE=$(strace openssl verify 2checkout.com-0.crt </dev/null 2>&1 |grep -v getpid |grep -A1 'rt_sigaction(SIGPIPE,' |tail -n1 |sed 's%open("\([^"]*\)".*%\1%g')
  cat $SYSTEM_BUNDLE ${OK_CERTS[@]:0} >tmp-bundle.crt
  for ((i=0;i<${#NOTOK_CERTS[@]};i++)); do
    S=`openssl verify -verbose -cafile tmp_bundle.crt ${NOTOK_CERTS[$i]} 2>/dev/null |grep -v 'OK'`
    if [[ "${S}" != "" ]]; then
      echo ${S} |grep 'unable to get local issuer certificate' >/dev/null 2>&1
      test $? -eq 0 && echo "-- ${HOST}-${i}.crt: Error: Missing or incomplete CA chain" || echo "-- ${S}"
    else
      echo "++ ${HOST}-${i}.crt: OK"
    fi
  done
  rm -f tmp-bundle.crt
  echo
fi

# convert to text for any post run manual review
for (( i=0; i<${COUNT}; i++ )); do
  openssl x509 -in ${HOST}-${i}.crt -noout -text > ${HOST}-${i}.txt
done

# process certs
echo "Extended Processing"
echo
for (( i=0; i<${COUNT}; i++ )); do
  ISSUER=`grep 'Issuer: ' ${HOST}-${i}.txt`
  if [[ ${MATCH} -eq 1 && "`echo \"$ISSUER\" | grep -ie ${FILTER}`" == "" ]]; then continue; fi
  MATCHCOUNT=$(( ${MATCHCOUNT}+1 ))
  MATCHLIST="${MATCHLIST} ${HOST}-${i}.crt"
  echo -ne "  FILE: ${HOST}-${i}.crt ${HOST}-${i}.txt\n  "
  grep 'SUBJECT: ' ${HOST}-${i}.txt |sed 's%^[ ]*%%g'
  echo ${ISSUER} |sed -r 's%^ *%%g' |sed 's%Issuer%ISSUER%g'
  echo -n "  "
  grep 'Signature Algorithm: ' ${HOST}-${i}.txt | head -n1 |sed 's%^[ ]*%%g' |sed 's%Signature Algorithm%SIGNATURE ALGORITHM%'
  echo
done

echo "Done"
echo
if [[ ${MATCH} -eq 1 ]]; then
  echo "Matched: ${MATCHCOUNT}/${COUNT}"
  echo "List: ${MATCHLIST}"
  echo
fi

exit 0
