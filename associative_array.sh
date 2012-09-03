#!/bin/sh

# emulate associative arrays
#
# William Strucke, wstrucke@gmail.com
# Version 1.0, 2012


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
#   create an alias like so
#     alias KVSTORE='kv'
#
function kv {
  # magic :)
  __LN=$( caller 0 |awk '{print $1}' )
  __VAR=$( head -n${__LN} $0 |tail -n1 |sed 's/if\ \[\ //' |perl -pe 's/(?:[^\(\`]*[\(\`]?)?? ?([^\ \t(\`=]*)( |\n).*/\1/' )
  __KVK="__${__VAR}_K"; __KVV="__${__VAR}_V"
  # __KVK/KVV is now a custom array store for the name of the variable this function was aliased to
  test $# -eq 0 && return || test -z ${!__KVK} && typeset -ax ${!__KVK} ${!__KVV}
  if [ $# -eq 1 ]; then
    eval __C=\${#${__KVK}[@]}
    for (( __i=0;__i<$__C;__i++ )); do eval __V="\${${__KVK}[$__i]}"
      if [ "$__V" == "$1" ]; then eval __V="\${${__KVV}[$__i]}"; echo "$__V"; return; fi
    done
  else
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
