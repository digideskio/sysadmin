#!/bin/sh

# verify and convert RRD databases between architectures
#
# version 1.0.0, wstrucke 2011-08-09
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
# dependencies (must be in path):
#  /bin/basename
#  /bin/cat
#  /bin/cp
#  /bin/egrep
#  /bin/grep
#  /bin/ls
#  /bin/mkdir
#  /bin/pwd
#  /bin/rm
#  /bin/sed
#  /bin/tar
#  /bin/uname
#  /sbin/ip
#  /usr/bin/awk
#  /usr/bin/bzip2
#  /usr/bin/bunzip2
#  /usr/bin/dirname
#  /usr/bin/expect
#  /usr/bin/expr
#  /usr/bin/find
#  /usr/bin/scp
#  /usr/bin/shred
#  /usr/bin/ssh
#  /usr/bin/sudo
#  /usr/local/rrdtool/bin/rrdtool
#
#
# requires:
#  -end     ip of the other endpoint. optionally the ip of this endpoint
#           can be provided as well by specifying this argument twice.
#  -uid     user name to auth as. must have sudo access on all systems
#  -path    rrd file or directory to index
#
# optional:
#  -relay   ip to use as an intermediary between the 32/64 hosts
#           this can be provided one or two times if there are two hosts between
#           the endpoints. three+ would require additional logic in the script.
#           for safety and security the files will be archived prior to deletion!
#  -max-files
#           specify the maximum number of databases to convert. useful if
#           either the source or destination box has low disk space or memory.
#  -tmp-path
#           manually specify a temporary path to use, i.e. "/tmp" [default]
#           useful if the normal tmp doesn't have enough disk space
#
#
# run down:
#  - check the input path
#    - if rrd-convert-shipping.tar.bz2 set AUTO flag to TRUE
#    - else build file list
#  - identify what architecture this script was started from
#  - identify which host this was started on
#  - if an endpoint:
#    - create the shipping archive
#    - compile the list of files
#    - for each file:
#      - if architecture matches host architecture and auto flag is set convert the file
#        and add to the shipping archive
#      - if architecture does not match this host and auto flag is not set, add the file
#        to the shipping archive
#  - ship this script and the archive to the next hop and execute
#  - if this is the source (AUTO is FALSE)
#    - backup the original files and restore the xml
#
# recursion:
#  ** this script calls itself after deploying to another server **
#  - in a typical scenario, execution would be as follows:
#    I. Started on SERVER A (source)
#    I. SERVER A performs data processing and creates the data tarball
#    I. SERVER A deploys the script and the data tarball to RELAY A
#       II. RELAY A ships the script and the tarball to RELAY B
#           III. RELAY B ships the script and the tarball to SERVER B (dest)
#                IV. SERVER B performs the data processing
#                IV. SERVER B ships the new tarball back to RELAY B and exits (OK or ERROR)
#           III. RELAY B exits with the SERVER B exit status and text
#       II. RELAY A exits with the RELAY B exit status and text
#    I. IFF OK SERVER A performs final data processing and exits
#
# credentials:
#  - this script requires a user id and password with root access on all systems it touches
#  - the credentials are *NEVER* passed in plain text and *NEVER* appear in the shell or
#    process list
#  - this script makes use of expect to enter the appropriate credentails interactively
#    during nested execution on remote systems
#  - in order to faciliate this behavior the password is written to a temporary file
#    by this script and read by the expect script.  that file is then immediately
#    destroyed and shredded
#

# notes:
#  - this script will fail if the destination end point shares a local ip (duh)
#  - ignore all of the destination = crap; that was based on a different execution model
#    it can't be removed, however, without reviewing the code completely

# functions
function end {
  if [ "$1" == "" ]; then log "Completed"; else log "$1"; fi
  if [ "$2" == "" ]; then RET=0; else RET=$2; fi
  # clean up
  if [ -f rrd-arch-scp.expect ]; then purgef rrd-arch-scp.expect; fi
  if [ -f rrd-arch-convert.expect ]; then purgef rrd-arch-convert.expect; fi
  if [ -f rrd-arch-convert.params ]; then purgef rrd-arch-convert.params; fi
  if [ -f rrd-arch-convert.pwd ]; then purgef rrd-arch-convert.pwd; fi
  if [ -d $TMPPATH ]; then /bin/rm -Rf $TMPPATH; fi
  exit $RET
}

function usage {
  echo "  Usage: $0 -uid -path -end [-end] [-relay] [-relay]"
  exit 0
}

function log {
  /usr/bin/logger -t "rrd-arch-convert" $1
  echo $1
}

function sendscript {
  # $1 = ip
  # $2 = user id
  echo "...Sending script to $1"
  if [ ! -f rrd-arch-scp.expect ]; then writeexpect $2; fi
  /usr/bin/expect -f rrd-arch-scp.expect $1 $2 `/bin/basename $0`
  return
}

function sendarchive {
  # $1 = ip
  # $2 = path to archive
  # $3 = user id
  echo "...Sending archive to $1"
  if [ ! -f rrd-arch-scp.expect ]; then writeexpect $3; fi
  /usr/bin/expect -f rrd-arch-scp.expect $1 $3 $2
  return
}

function purgef {
  # shred a file from the disk
  # $1 = file name and path
  if [[ "$1" == "" || "$1" == "/" || ! -f "$1" ]]; then echo "Bad Path"; return 0; fi
  /usr/bin/shred -uz "$1"
  return 0;
}

function writeexpect {
  # write the expect script to disk
  # doing it here to avoid having to scp a seperate file
  cat <<_EOF > rrd-arch-scp.expect
#!/usr/bin/expect -f
log_user 0
set timeout 3600
set fp [open "rrd-arch-convert.pwd" r]
set pwd [read \$fp]
close \$fp
set addr [lrange \$argv 0 0]
set userid [lrange \$argv 1 1]
set file [lrange \$argv 2 2]
spawn /usr/bin/scp \$file \$userid@\$addr:
while 1 {
expect {
        "The authenticity of host?" {}
        "ECDSA key fingerprint is?" {}
        "Are you sure you want to continue?" {send "yes\\n"}
        "*?assword:*" { exec sleep 1; send "\$pwd\\n"; break}
        eof { break }
        timeout { break }
}
}
send -- "\\n"
expect eof
_EOF
  cat <<_EOF-convert > rrd-arch-convert.expect
#!/usr/bin/expect -f
log_user 1
#exp_internal 1
set timeout 43200
set fp [open "rrd-arch-convert.pwd" r]
set pwd [read \$fp]
close \$fp
set fp [open "rrd-arch-convert.params" r]
set params [read \$fp]
close \$fp
set addr [lrange \$argv 0 0]
set userid [lrange \$argv 1 1]
spawn /usr/bin/ssh \$userid@\$addr
while 1 {
  expect {
    "The authenticity of host?" {}
    "ECDSA key fingerprint is?" {}
    "Are you sure you want to continue?" { send "yes\\r" }
    "*?assword:*" { send \$pwd; break }
    eof { break }
    timeout { break }
  }
}
expect "\\\\\\$"
# elevate priviledges
send "/usr/bin/sudo su\\r"
expect {
  "Password" { send \$pwd }
  "password for" { send \$pwd }
  "*#" { send "\\r" }
}
expect {
  "Sorry, try again." { send \003; break }
  "*#" {
    # start the next instance
    send "/bin/sh rrd-arch-convert.sh \$params\\r"
    expect "Enter Password:*"
    send \$pwd
    expect "Completed"
    expect "*#"
    send "exit\\r"
    }
}
expect "\\\\\\$"
send "exit\\r"
expect eof
_EOF-convert
  return
}

# permissions validation
if [ "`whoami`" != "root" ]; then end "You must be root to run this script."; fi

# initialize variables
ARCH=`/bin/uname -m`
ARGS=""
AUTO=0
DEST=""
DIRECTION=0
# direction: 0=source->dest, 1=dest->source
ENDPOINT=()
FILES=()
ID=""
LBTXT="=========================================================================="
LOGOUTCLEAR=0
MAXFILES=0
NEXTHOP=""
PW=""
RELAY=()
RRDPATH=""
SOURCE=""
THISNODE=0
# node modes: 0=Source, 1=Destination, 2=relay
TMPPATH=/tmp/rrdconvert
TMPROOT=/tmp

# relay arguments
while [ $1 ]; do
  case "$1" in
    -end)
      # set an endpoint
      ENDPOINT[${#ENDPOINT[@]}]="$2"
      ;;
    -uid)
      ID="$2"
      ;;
    -path)
      RRDPATH="$2"
      ;;
    -relay)
      # set a relay
      RELAY[${#RELAY[@]}]="$2"
      ;;
    -direction)
      # set the transfer direction
      DIRECTION=$2
      ;;
    -max-files)
      # set the maximum number of files
      MAXFILES=$2
      ;;
    -tmp-path)
      # set the temporary path
      if [[ -d "$2" && ! -d "$1/rrdconvert" ]]; then
        TMPPATH="$2/rrdconvert"
        TMPROOT="$2"
      else
        end "Unable to validate the provided temporary path" -1
      fi
      ;;
    *)
      usage;
      ;;
  esac
  shift;
  shift;
done

# validate input
if [ ${#ENDPOINT[@]} -eq 0 ]; then end "Too few endpoints"; fi
if [ ${#ENDPOINT[@]} -gt 2 ]; then end "Too many endpoints"; fi
if [ ${#RELAY[@]} -gt 2 ]; then end "Too many relays"; fi
if [ "$ID" == "" ]; then end "A user id is required"; fi
if [ "$RRDPATH" == "" ]; then end "A path is required"; fi
if [ -d $TMPPATH ]; then end "The temporary path at $TMPPATH already exists, aborting"; fi

# get the password
read -sp "Enter Password: " PW
# run the pw through col to remove the ^M character that appears when running through expect -> sh -> ssh -> expect -> etc...
echo "$PW" | /usr/bin/col -b > rrd-arch-convert.pwd
echo ""

#echo "there are ${#ENDPOINT[@]} endpoints"
#for (( i=0 ; i<${#ENDPOINT[@]} ; i++ )); do
#  echo "Endpoint: ${ENDPOINT[${i}]}"
#done

# check the input path
if [ -f $RRDPATH ]; then
  if [ "$RRDPATH" == "rrd-convert-shipping.tar.bz2" ]; then
    # this is a relay or the final endpoint
    AUTO=1
  else
    # script started on the source host processing one file
    FILES=( $RRDPATH )
  fi
elif [ -d $RRDPATH ]; then
  # script started on the source host processing multiple files
  FILES=( `/usr/bin/find $RRDPATH -name *.rrd -print | /bin/sed 's/ /\\ /g'` )
  # note -- this is the most efficient way to load the file list into an array
  # the caveat is that any file name with a space will have to be handled specially.
  # the sed here will put a '\' at the end of any path with a space, then the path
  # will be continued on the next array item.  this could include multiple lines
  # depending on the number of spaces so that will have to be accounted for.
else
  end "Invalid path provided"
fi

#echo "there are ${#FILES[@]} files"
#for (( i=0 ; i<${#FILES[@]} ; i++ )); do
#  echo "File: ${FILES[${i}]}"
#done
#echo ""

# identify which host the script was started on (identify source and dest)
if [ $AUTO -eq 0 ]; then
  THISNODE=0
  if [ "`/sbin/ip addr sh | /bin/grep \"${ENDPOINT[0]}\"`" == "" ]; then
    DEST=${ENDPOINT[0]}
  elif [[ ${#ENDPOINT[@]} -eq 2 && "`/sbin/ip addr sh | /bin/grep \"${ENDPOINT[1]}\"`" == "" ]]; then
    end "Error: neither end point corresponds to the local host and I'm not a relay!"
  else
    SOURCE=${ENDPOINT[0]}
    DEST=${ENDPOINT[1]}
  fi
  # determine the source ip
  if [ "$SOURCE" == "" ]; then
    SOURCE="`/sbin/ip addr sh | /bin/grep 'inet' | /bin/egrep -v '(secondary|lo$)' | /usr/bin/awk '{ print $2 }' | /usr/bin/awk 'BEGIN { FS="/"; } { print $1 }'`"
  fi
  if [ "$SOURCE" == "" ]; then end "Unable to determine my ip. Please provide it in the arguments or abort"; fi
else
  # this is a relay or the other endpoint
  if [ ${#ENDPOINT[@]} -ne 2 ]; then end "Error: both endpoints are required in auto mode"; fi
  SOURCE=${ENDPOINT[0]}
  DEST=${ENDPOINT[1]}
  if [[ "`/sbin/ip addr sh | /bin/grep \"${ENDPOINT[1]}\"`" == "" ]]; then
    # i am a relay
    THISNODE=2
  else
    THISNODE=1
  fi
fi

# build the arg (param) list for the next hop
ARGS="-end ${SOURCE}"
if [ ${#RELAY[@]} -gt 0 ]; then ARGS="${ARGS} -relay ${RELAY[0]}"; fi
if [ ${#RELAY[@]} -gt 1 ]; then ARGS="${ARGS} -relay ${RELAY[1]}"; fi
ARGS="${ARGS} -end ${DEST} -uid ${ID} -path rrd-convert-shipping.tar.bz2 -tmp-path $TMPROOT"

# take action
if [ $THISNODE -eq 0 ]; then
  echo ""
  echo "$LBTXT"
  echo "SOURCE"
  # check/set clear at logout
  if [ "`egrep '^clear$' /root/.bash_logout`" == "clear" ]; then
    LOGOUTCLEAR=1
    sed -i 's/clear/#clear/g' /root/.bash_logout
  fi
  # source
  if [ $DIRECTION -eq 0 ]; then
    # starting out
    # get the original files
    #   this block of code handles the file names being split due to the way they are enumerated
    #   its overly complicated but the logic is simple and simplifies code elsewhere
    #   maybe something to revisit someday. (perhaps better use of $IFS?)
    #   all other iterations of this script process a list of files provided by this instance,
    #   thus this doesn't have to happen anywhere else.
    #
    # intialize the master list
    SOURCELIST=()
    # initialize the local temp folder
    /bin/mkdir -p $TMPPATH
    # popuplate the list of files accounting for line breaks
    for (( i=0 ; i<${#FILES[@]} ; i++ )); do
      SKIP=0
      # if the next item exists and does not start with '/', include it here and skip the next one
      RRDPATH=${FILES[${i}]}
      CHECKSTR=""
      NEXT=$(($i+1))
      if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
      if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:1}; else FIRSTCHR=""; fi
      while [[ "$CHECKSTR" != "" && "$FIRSTCHR" != "/" ]]; do
        # append to the path with a space
        RRDPATH="$RRDPATH $CHECKSTR"
        # iterate the skip qualifier
        SKIP=$(($SKIP + 1))
        # check again
        NEXT=$((${i}+${SKIP}+1))
        CHECKSTR=""
        if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
        if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:1}; else FIRSTCHR=""; fi
      done
      # check the architecture of the file
      if [[ "`/usr/local/rrdtool/bin/rrdtool info \"$RRDPATH\" 2>&1`" == "ERROR: This RRD was created on other architecture" ]]; then
        # final path
        SOURCELIST[${#SOURCELIST[@]}]=$RRDPATH
        # make the dest directory as needed
        /bin/mkdir -p "${TMPPATH}`/usr/bin/dirname \"${RRDPATH}\"`"
        # copy the file
        /bin/cp -i "${RRDPATH}" "${TMPPATH}${RRDPATH}"
      fi
      # iterate i by skip
      i=$(($i+$SKIP))
      # check optional file limit
      if [[ $MAXFILES -ne 0 && ${#SOURCELIST[@]} -ge $MAXFILES ]]; then i=${#FILES[@]}; fi
    done
    # create the shipping tarbal
    CURDIR=`/bin/pwd`
    cd $TMPPATH
    # handle special case where there is nothing to do
    if [ ${#SOURCELIST[@]} -eq 0 ]; then cd $CURDIR; /bin/rm -Rf $TMPPATH; end "There are no files to convert"; fi
    /bin/tar cjf "$TMPROOT/rrd-convert-shipping.tar.bz2" *
    if [ $? -ne 0 ]; then
      if [ $LOGOUTCLEAR -eq 1 ]; then sed -i 's/#clear/clear/g' /root/.bash_logout; fi
      echo ""; end "Unrecoverable error creating archive; aborting" -1;
    fi
    #/usr/bin/bzip2 -z "$TMPROOT/rrd-convert-shipping.tar"
    #if [ $? -ne 0 ]; then echo ""; end "Unrecoverable error compressing archive; aborting" -1; fi
    cd $CURDIR
    # clean up temp files
    /bin/rm -Rf $TMPPATH
    # determine the next hop
    if [ ${#RELAY[@]} -gt 0 ]; then NEXTHOP=${RELAY[0]}; else NEXTHOP=$DEST; fi
    # ship the script to the next hop
    sendscript $NEXTHOP $ID $PW
    # ship the archive to the next hop
    sendarchive $NEXTHOP "$TMPROOT/rrd-convert-shipping.tar.bz2" $ID "$PW"
    # clean up
    if [ -f "$TMPROOT/rrd-convert-shipping.tar.bz2" ]; then purgef "$TMPROOT/rrd-convert-shipping.tar.bz2"; fi
    # write the param file (arguments for this script on the next hop)
    echo "$ARGS -direction 0" > rrd-arch-convert.params
    # execute this script on the next hop
    /usr/bin/expect -f rrd-arch-convert.expect $NEXTHOP $ID
    if [ $LOGOUTCLEAR -eq 1 ]; then sed -i 's/#clear/clear/g' /root/.bash_logout; fi
    # if results were returned, process them
    if [ -f rrd-convert-shipping.tar.bz2 ]; then
      /bin/mkdir -p $TMPPATH
      /bin/tar xjf rrd-convert-shipping.tar.bz2 -C $TMPPATH
      cd $TMPPATH
      # enumarate the files to process
      FILES=( `/usr/bin/find . -name *.xml -print | /bin/sed 's/ /\\ /g'` )
      # set counter
      COUNT=0
      for (( i=0 ; i<${#FILES[@]} ; i++ )); do
        SKIP=0
        # if the next item exists and does not start with './', include it here and skip the next one
        RRDPATH=${FILES[${i}]}
        CHECKSTR=""
        NEXT=$(($i+1))
        if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
        if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:2}; else FIRSTCHR=""; fi
        while [[ "$CHECKSTR" != "" && "$FIRSTCHR" != "./" ]]; do
          # append to the path with a space
          RRDPATH="$RRDPATH $CHECKSTR"
          # iterate the skip qualifier
          SKIP=$(($SKIP + 1))
          # check again
          NEXT=$((${i}+${SKIP}+1))
          CHECKSTR=""
          if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
          if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:2}; else FIRSTCHR=""; fi
        done
        # remove the leading "./" from the RRDPATH
        RRDPATH=${RRDPATH:2}
        # make sure the corresponding original file exists
        ORIGINAL="/`echo ${RRDPATH} | /bin/sed s/\.xml/\.rrd/i`"
        # account for all uppercase file extensions
        if [ ! -f "$ORIGINAL" ]; then ORIGINAL="/`echo ${RRDPATH} | /bin/sed s/\.xml/\.RRD/i`"; fi
        if [ -f "$ORIGINAL" ]; then
          # archive the old file
          mv "$ORIGINAL" "$ORIGINAL.badarch"
          # convert the file and output to the new path
          /usr/local/rrdtool/bin/rrdtool restore "${RRDPATH}" "${ORIGINAL}"
          COUNT=$(($COUNT + 1))
        fi
        # iterate i by skip
        i=$(($i+$SKIP))
      done
      # clean up
      if [ -d $TMPPATH ]; then /bin/rm -rf $TMPPATH; fi
      # status
      echo ""
      echo "$LBTXT"
      echo "Converted ${COUNT} RRD(s)"
    fi
  fi
elif [ $THISNODE -eq 2 ]; then
  # relay
  echo ""
  echo "$LBTXT"
  echo -n "RELAY: "
  # make sure the file exists
  if [ ! -f rrd-convert-shipping.tar.bz2 ]; then end "Error: Shipping Archive is Missing" -1; fi
  # send this script and the archive to the next endpoint and execute
  if [ ${#RELAY[@]} -eq 1 ]; then
    # send to the next endpoint
    if [ $DIRECTION -eq 0 ]; then NEXTHOP=$DEST; RETPATH=$SOURCE; else NEXTHOP=$SOURCE; fi
  else
    if [ "`/sbin/ip addr sh | /bin/grep \"${RELAY[0]}\"`" == "" ]; then
      # this is the second relay in the chain
      echo -n "2: "
      if [ $DIRECTION -eq 0 ]; then NEXTHOP=$DEST; RETPATH=${RELAY[0]}; else NEXTHOP=$SOURCE; fi
    else
      NEXTHOP=${RELAY[1]}
      RETPATH=$SOURCE
    fi
  fi
  echo -n "Source: ${SOURCE} "
  echo -n "Next hop: ${NEXTHOP} "
  echo "Return path: ${RETPATH} "
  # only send the script if the next hop is something other than the first hop
  if [ "$NEXTHOP" != "$SOURCE" ]; then sendscript $NEXTHOP $ID $PW; fi
  sendarchive $NEXTHOP rrd-convert-shipping.tar.bz2 $ID $PW;
  # clean up
  if [ -f rrd-convert-shipping.tar.bz2 ]; then purgef rrd-convert-shipping.tar.bz2; fi
  # write the param file (arguments for this script on the next hop)
  echo "$ARGS -direction 0" > rrd-arch-convert.params
  # execute this script on the next hop
  /usr/bin/expect -f rrd-arch-convert.expect $NEXTHOP $ID
  # check for the returned tarball
  if [ -f rrd-convert-shipping.tar.bz2 ]; then
    # send back to whence we came
    sendarchive $RETPATH rrd-convert-shipping.tar.bz2 $ID $PW;
    # clean up
    if [ -f rrd-convert-shipping.tar.bz2 ]; then purgef rrd-convert-shipping.tar.bz2; fi
  else
    end "Error: no return archive" -1
  fi
  # done
  end
else
  # endpoint -- do the conversion
  echo ""
  echo "$LBTXT"
  echo "DEST"
  # create the temp folder
  /bin/mkdir -p $TMPPATH/original $TMPPATH/processed
  # unpack the shipped data for processing
  /bin/tar xjf rrd-convert-shipping.tar.bz2 -C $TMPPATH/original
  # clean up
  if [ -f rrd-convert-shipping.tar.bz2 ]; then purgef rrd-convert-shipping.tar.bz2; fi
  # cache the path
  CURDIR=`/bin/pwd`
  # change into the original directory
  cd $TMPPATH/original
  # enumarate the files to process
  FILES=( `/usr/bin/find . -name *.rrd -print | /bin/sed 's/ /\\ /g'` )
  for (( i=0 ; i<${#FILES[@]} ; i++ )); do
    SKIP=0
    # if the next item exists and does not start with './', include it here and skip the next one
    RRDPATH=${FILES[${i}]}
    CHECKSTR=""
    NEXT=$(($i+1))
    if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
    if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:2}; else FIRSTCHR=""; fi
    while [[ "$CHECKSTR" != "" && "$FIRSTCHR" != "./" ]]; do
      # append to the path with a space
      RRDPATH="$RRDPATH $CHECKSTR"
      # iterate the skip qualifier
      SKIP=$(($SKIP + 1))
      # check again
      NEXT=$((${i}+${SKIP}+1))
      CHECKSTR=""
      if [[ $NEXT -lt ${#FILES[@]} ]]; then CHECKSTR=${FILES[${NEXT}]}; fi
      if [[ "$CHECKSTR" != "" ]]; then FIRSTCHR=${CHECKSTR:0:2}; else FIRSTCHR=""; fi
    done
    # remove the leading "./" from the RRDPATH
    RRDPATH=${RRDPATH:2}
    # check the architecture of the file
    if [[ "`/usr/local/rrdtool/bin/rrdtool info \"$RRDPATH\" 2>&1`" != "ERROR: This RRD was created on other architecture" ]]; then
      # make the dest directory as needed
      /bin/mkdir -p "${TMPPATH}/processed/`/usr/bin/dirname \"${RRDPATH}\"`" 2>&1 1>/dev/null
      # convert the file and output to the new path
      /usr/local/rrdtool/bin/rrdtool dump "${RRDPATH}" > "${TMPPATH}/processed/`echo ${RRDPATH} | /bin/sed s/\.rrd/\.xml/i`"
    fi
    # iterate i by skip
    i=$(($i+$SKIP))
  done
  # create the shipping tarbal
  cd $TMPPATH/processed
  /bin/tar cjf "$TMPROOT/rrd-convert-shipping.tar.bz2" *
  if [ $? -ne 0 ]; then echo ""; end "Unrecoverable error creating archive; aborting" -1; fi
  #/usr/bin/bzip2 -z "$TMPROOT/rrd-convert-shipping.tar"
  #if [ $? -ne 0 ]; then echo ""; end "Unrecoverable error compressing archive; aborting" -1; fi
  # switch back to the original source directory
  cd $CURDIR
  # clean up temp files
  /bin/rm -Rf $TMPPATH
  # determine the next hop
  if [ ${#RELAY[@]} -eq 2 ]; then NEXTHOP=${RELAY[1]}; elif [ ${#RELAY[@]} -eq 1 ]; then NEXTHOP=${RELAY[0]}; else NEXTHOP=$SOURCE; fi
  # ship the archive to the next hop
  sendarchive $NEXTHOP "$TMPROOT/rrd-convert-shipping.tar.bz2" $ID "$PW"
  # clean up
  if [ -f "$TMPROOT/rrd-convert-shipping.tar.bz2" ]; then purgef "$TMPROOT/rrd-convert-shipping.tar.bz2"; fi
  # done
  end
fi

end
