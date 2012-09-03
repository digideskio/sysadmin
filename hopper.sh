#!/bin/sh

# move data around between hosts
# William Strucke, wstrucke@gmail.com
# version 1.0.0, 2011-08-09/2011-09-20
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
#
#
# requires:
#  -end     ip of the other endpoint. optionally the ip of this endpoint
#           can be provided as well by specifying this argument twice.
#  -uid     user name to auth as. must have sudo access on all systems
#  -path    file or directory to copy
#
# optional:
#  -relay   ip to use as an intermediary between the end point hosts
#           this can be provided one or two times if there are two hosts between
#           the endpoints. three+ would require additional logic in the script.
#
#
# run down:
#  - check the path exists
#  - identify which host this was started on
#  - if an endpoint:
#    - create the shipping archive
#    - compile the list of files
#  - ship this script and the archive to the next hop and execute
#
# recursion:
#  ** this script calls itself after deploying to another server **
#  - in a typical scenario, execution would be as follows:
#    I. Started on SERVER A (source)
#    I. SERVER A creates the data tarball
#    I. SERVER A deploys the script and the data tarball to RELAY A
#       II. RELAY A ships the script and the tarball to RELAY B
#           III. RELAY B ships the script and the tarball to SERVER B (dest)
#           III. RELAY B exits with the SERVER B exit status and text
#       II. RELAY A exits with the RELAY B exit status and text
#    I. IFF OK SERVER A cleans up and exits
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
#
# notes:
#  - this script will fail if the destination end point shares a local ip (duh)
#  - ignore all of the destination = crap; that was based on a different execution model
#    it can't be removed, however, without reviewing the code completely
#  - right now if a host has more than one primary IP (i.e. on multiple interfaces) the script
#    will chose the last one.  this is for no other reason than it makes the script work
#    on specific test hosts. A better way would be to enumerate the route table when there is more than one
#    primary IP and use the IP the server will use to route to the next hop. future task.
#

# functions
function end {
  if [ "$1" == "" ]; then log "Ending (Unknown Node)"; fi
  if [ "$2" == "" ]; then log "Completed"; else log "$2"; fi
  if [ "$3" == "" ]; then RET=0; else RET=$3; fi
  # clean up
  if [[ $1 -gt 0 && -f hopper.sh ]]; then purgef hopper.sh; fi
  if [ -f hopper.expect ]; then purgef hopper.expect; fi
  if [ -f hopper-scp.expect ]; then purgef hopper-scp.expect; fi
  if [ -f hopper.params ]; then purgef hopper.params; fi
  if [ -f hopper.pwd ]; then purgef hopper.pwd; fi
  exit $RET
}

function usage {
  echo "  Usage: $0 -uid -path -end [-end] [-relay] [-relay]"
  exit 0
}

function log {
  /usr/bin/logger -t "hopper" $1
  echo $1
}

function sendscript {
  # $1 = ip
  # $2 = user id
  echo "...Sending script to $1"
  if [ ! -f hopper-scp.expect ]; then writeexpect $2; fi
  FILE=`/bin/basename $0`
  if [ ! -f $FILE ]; then FILE=`which ${FILE}`; fi
  /usr/bin/expect -f hopper-scp.expect $1 $2 $FILE
  return
}

function sendarchive {
  # $1 = ip
  # $2 = path to archive
  # $3 = user id
  echo "...Sending archive to $1"
  if [ ! -f hopper-scp.expect ]; then writeexpect $3; fi
  /usr/bin/expect -f hopper-scp.expect $1 $3 $2
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
  cat <<_EOF > hopper-scp.expect
#!/usr/bin/expect -f
log_user 0
set timeout 3600
set fp [open "hopper.pwd" r]
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
  cat <<_EOF-convert > hopper.expect
#!/usr/bin/expect -f
log_user 1
#exp_internal 1
set timeout 43200
set fp [open "hopper.pwd" r]
set pwd [read \$fp]
close \$fp
set fp [open "hopper.params" r]
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
    send "/bin/sh hopper.sh \$params\\r"
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
if [ "`whoami`" != "root" ]; then end 0 "You must be root to run this script."; fi

# initialize variables
ARCH=`/bin/uname -m`
ARGS=""
AUTO=0
DEST=""
DIRECTION=2
# direction: 0=source->dest, 1=dest->source
ENDPOINT=()
FILES=()
ID=""
LBTXT="=========================================================================="
LOGOUTCLEAR=0
NEXTHOP=""
PW=""
RELAY=()
DATAPATH=""
SOURCE=""
THISNODE=0
# node modes: 0=Source, 1=Destination, 2=relay

# make sure arguments were provided
if [ $# -eq 0 ]; then usage; fi

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
      DATAPATH="$2"
      ;;
    -relay)
      # set a relay
      RELAY[${#RELAY[@]}]="$2"
      ;;
    -direction)
      # set the transfer direction
      DIRECTION=$2
      ;;
    *)
      usage;
      ;;
  esac
  shift;
  shift;
done

# validate input
if [ ${#ENDPOINT[@]} -eq 0 ]; then end 0 "Too few endpoints"; fi
if [ ${#ENDPOINT[@]} -gt 2 ]; then end 0 "Too many endpoints"; fi
if [ ${#RELAY[@]} -gt 2 ]; then end 0 "Too many relays"; fi
if [ "$ID" == "" ]; then end 0 "A user id is required"; fi
if [ "$DATAPATH" == "" ]; then end 0 "A path is required"; fi

# get the password
read -sp "Enter Password: " PW
# run the pw through col to remove the ^M character that appears when running through expect -> sh -> ssh -> expect -> etc...
echo "$PW" | /usr/bin/col -b > hopper.pwd
echo ""

#echo "there are ${#ENDPOINT[@]} endpoints"
#for (( i=0 ; i<${#ENDPOINT[@]} ; i++ )); do
#  echo "Endpoint: ${ENDPOINT[${i}]}"
#done

# check the input path
if [ -e $DATAPATH ]; then
  if [ $DIRECTION -lt 2 ]; then
    # this is a relay or the final endpoint
    AUTO=1
  else
    DIRECTION=0
  fi
else
  end 0 "Invalid path provided"
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
    end 0 "Error: neither end point corresponds to the local host and I'm not a relay!"
  else
    SOURCE=${ENDPOINT[0]}
    DEST=${ENDPOINT[1]}
  fi
  # determine the source ip
  if [ "$SOURCE" == "" ]; then
    SOURCE="`/sbin/ip addr sh | /bin/grep 'inet' | /bin/egrep -v '(secondary|lo$)' | /usr/bin/awk '{ print $2 }' | /usr/bin/awk 'BEGIN { FS="/"; } { print $1 }' | tail -n1`"
  fi
  if [ "$SOURCE" == "" ]; then end 0 "Unable to determine my ip. Please provide it in the arguments or abort"; fi
else
  # this is a relay or the other endpoint
  if [ ${#ENDPOINT[@]} -ne 2 ]; then end 0 "Error: both endpoints are required in auto mode"; fi
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
ARGS="${ARGS} -end ${DEST} -uid ${ID}"

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
    if [ -d $DATAPATH ]; then
      # create the shipping tarball
      /bin/tar cjf hopper-shipping.tar.bz2 $DATAPATH
      if [ $? -ne 0 ]; then
        if [ $LOGOUTCLEAR -eq 1 ]; then sed -i 's/#clear/clear/g' /root/.bash_logout; fi
        echo ""; end 0 "Unrecoverable error creating archive; aborting" -1;
      fi
      DATAPATH="hopper-shipping.tar.bz2"
    fi
    # determine the next hop
    if [ ${#RELAY[@]} -gt 0 ]; then NEXTHOP=${RELAY[0]}; else NEXTHOP=$DEST; fi
    # write the param file (arguments for this script on the next hop)
    echo "${ARGS} -path `basename ${DATAPATH}` -direction 0" > hopper.params
    # ship the script to the next hop
    sendscript $NEXTHOP $ID $PW
    # ship the archive to the next hop
    sendarchive $NEXTHOP $DATAPATH $ID "$PW"
    # clean up
    if [ -f hopper-shipping.tar.bz2 ]; then purgef hopper-shipping.tar.bz2; fi
    # execute this script on the next hop
    /usr/bin/expect -f hopper.expect $NEXTHOP $ID
    if [ $LOGOUTCLEAR -eq 1 ]; then sed -i 's/#clear/clear/g' /root/.bash_logout; fi
  fi
elif [ $THISNODE -eq 2 ]; then
  # relay
  echo ""
  echo "$LBTXT"
  echo -n "RELAY: "
  # make sure the file exists
  if [ ! -f ${DATAPATH} ]; then end 2 "Error: Shipping Archive is Missing" -1; fi
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
  sendarchive $NEXTHOP $DATAPATH $ID $PW;
  # clean up
  if [ -f ${DATAPATH} ]; then purgef ${DATAPATH}; fi
  # write the param file (arguments for this script on the next hop)
  echo "$ARGS -path ${DATAPATH} -direction 0" > hopper.params
  # execute this script on the next hop
  /usr/bin/expect -f hopper.expect $NEXTHOP $ID
  # done
  end 2
else
  # endpoint
  echo ""
  echo "$LBTXT"
  echo "DEST"
  if [ -f hopper-shipping.tar.bz2 ]; then
    # unpack the shipped data for processing
    /bin/tar xjf hopper-shipping.tar.bz2
    # clean up
    purgef hopper-shipping.tar.bz2
  fi
  # done
  end 1
fi

end 0
