#!/bin/sh

# control nagios monitoring (enable/disable service notifications)
#
# William Strucke, wstrucke@gmail.com
# Version 1.1.0, 2012-03-01
#
# Requires:
#   host-name(s) (enable|disable)
#
# Command Reference:
#   http://old.nagios.org/developerinfo/externalcommands/commandlist.php
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

function usage {
  IFS=$FS_CACHE
  echo "Usage: $0 host-name(s) (enable|disable)"
  exit 1
}

# set statics
FS_CACHE="$IFS"
LIST=""
NL=$'\n'
NOW=`date +%s`
SOURCE_DIR=`dirname $0`
TAB=$'\t'

# load arguments
while [ $1 ]; do
  if [ $# -eq 1 ]; then break; else LIST="$LIST $1"; fi
  shift;
done
COMMAND="$1"

# validate input
if [ "$LIST" == "" ]; then usage; fi
if [ ! -f $SOURCE_DIR/.nagiosmap ]; then echo "Missing nagiosmap!"; exit 1; fi

case $COMMAND in
  enable) CMD="ENABLE_SVC_NOTIFICATIONS";;
  disable) CMD="DISABLE_SVC_NOTIFICATIONS";;
  disable-all) CMD="DISABLE_NOTIFICATIONS";;
  enable-all) CMD="ENABLE_NOTIFICATIONS";;
  *) usage;;
esac;

# validate input
if [[ "$COMMAND" == "enable-all" || "$COMMAND" == "disable-all" ]]; then
  for SERVER in $LIST; do
    ssh $SERVER "/usr/bin/printf \"[%lu] ${CMD};$NOW\n\" $NOW > /usr/local/nagios/var/rw/nagios.cmd"
  done
  echo "Command:    $CMD"
  exit 0
fi

for SERVER in $LIST; do
  grep -Eq "^${SERVER}${TAB}" $SOURCE_DIR/.nagiosmap
  if [ $? -ne 0 ]; then
    echo "Error: the host name you provided is not in the nagiosmap file. Did you mean the OOC config (hostname-ooc)?";
    exit 1
  fi
done

for SERVER in $LIST; do
  IFS=$NL
  for M in `grep -E "^${SERVER}${TAB}" $SOURCE_DIR/.nagiosmap`; do
    LB=`echo $M | awk 'BEGIN { FS="\t" } { print $2 }'`
    NODE=`echo $M | awk 'BEGIN { FS="\t" } { print $3 }'`
    SERVICES=`echo $M | awk 'BEGIN { FS="\t" } { print $4 }'`
    IFS=" "
    for S in $SERVICES; do
      if [ "$COMMAND" == "enable" ]; then
        # also force service check
        ssh $NODE "/usr/bin/printf \"[%lu] SCHEDULE_FORCED_SVC_CHECK;${LB};${S};$NOW\n\" $NOW > /usr/local/nagios/var/rw/nagios.cmd"
      fi
      ssh $NODE "/usr/bin/printf \"[%lu] ${CMD};${LB};${S}\n\" $NOW > /usr/local/nagios/var/rw/nagios.cmd"
    done
    IFS=$NL
    # summary
    echo "Nagios Node: $NODE"
    echo "Server:      $SERVER"
    echo "Services:    $SERVICES"
    echo "Command:     $CMD"
    echo
  done
done

# add a delay to allow the event to take effect
if [ "$COMMAND" == "disable" ]; then sleep 60; fi

IFS=$FS_CACHE
exit 0
