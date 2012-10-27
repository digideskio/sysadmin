#!/bin/sh

# emulate associative arrays
#
# William Strucke, wstrucke@gmail.com
# Version 1.0.1
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

# set
#   blah[test1] = 'this is a test'
#   blah[test2] = 'another test'
#
# get
#   blah[test1]
#   blah[test2]
#

# kv
#   simple bash key/value store
#
#   you can alias this function to use multiple key/value stores in the same script,
#   the caveat being that each call to this function or an alias must be on its own
#   line in the script (since we're using head/tail to get the value)
#
#   valid calls include (substitute alias for 'kv' as needed, args are optional):
#     kv arg1 arg2
#     VAL=`kv arg1 arg2`
#     VAL=$( kv arg1 arg2 )
#     if [ $( kv ...
#
#   display array keys:
#     kv
#
#   set a key/value:
#     kv KEY VAL
#
#   retrieve a value:
#     kv KEY
#
#   create an alias like so
#     alias KVSTORE='kv'
#
function kv {
  # magic :)
  __LN=$( caller 0 |awk '{print $1}' )
  __VOPT=(); __VOPT[0]='kv'; __VAR=""
  echo -n "" |sed -r 's/^//' >/dev/null 2>&1 && SED='sed -r' || SED='sed -E'
  for __V in $( grep -iE "^[^#](.*[[:space:]]*)?a?lias[[:space:]].*=['\"]?kv['\"]?([[:space:]]|$)" $BASH_SOURCE |$SED 's/.*alias ([^=]*)=.*/\1/' ); do
    __VOPT[${#__VOPT[@]}]=$__V; done
  __VSEL=$( head -n${__LN} $0 |tail -n1 )
  for ((__V=0;__V<${#__VOPT[@]};__V++)); do echo "$__VSEL" |grep -qE "(^|\t| )${__VOPT[$__V]}(\t| |$)"; test $? -eq 0 && __VAR=${__VOPT[$__V]}; done
  __KVK="__${__VAR}_K"; __KVV="__${__VAR}_V"
  # __KVK/KVV is now a custom array store for the name of the variable this function was aliased to
  test -z ${!__KVK} && typeset -ax ${!__KVK} ${!__KVV}
  # no arguments, return all keys
  if [ $# -eq 0 ]; then
    eval __C=\${#${__KVK}[@]}
    for (( __i=0;__i<$__C;__i++ )); do eval __V="\${${__KVK}[$__i]}"; echo "$__V"; done
    return
  fi
  if [ $# -eq 1 ]; then
    # one argument, return one key
    eval __C=\${#${__KVK}[@]}
    for (( __i=0;__i<$__C;__i++ )); do eval __V="\${${__KVK}[$__i]}"
      if [ "$__V" == "$1" ]; then eval __V="\${${__KVV}[$__i]}"; echo "$__V"; return; fi
    done
  else
    # two arguments, set a key
    eval __C=\${#${__KVK}[@]}
    for (( __i=0;__i<$__C;__i++ )); do eval __V="\${${__KVK}[$__i]}"
      if [ "$__V" == "$1" ]; then eval ${__KVV}[$__i]=\"$2\"; return; fi
    done
    eval ${__KVK}[$__C]=\"$1\"; eval ${__KVV}[$__C]=\"$2\"
  fi
  return
}

alias SUPERV='kv'

SUPERV test1 "this is a test"
SUPERV test1
SUPERV test2 "this is another test"
SUPERV test2
SUPERV test1

echo; echo "kv:"
kv test1

kv test1 "test test test"
VAL=$( kv test1 )
echo $VAL
kv test2 "another test"
VAL=$( kv test2 )
echo $VAL
