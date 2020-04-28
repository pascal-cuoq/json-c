#!/bin/bash
############################################################################
#                                                                          #
#  This file is part of TrustInSoft Analyzer.                              #
#                                                                          #
#    Copyright (C) 2017-2020 TrustInSoft                                   #
#                                                                          #
#  All rights reserved.                                                    #
#                                                                          #
############################################################################

set -o nounset

#===============================================================================
# Configuration:
#-------------------------------------------------------------------------------
classname="json-c.tests"

# TODO: optional: change directory
local_dir="$(dirname "$0")"
cd "$local_dir"

#-------------------------------------------------------------------------------
# Options:
#-------------------------------------------------------------------------------
# TODO: add options if needed (choose default value to be run in Jenkins)

# default values
clean=
verbosity="-v"

help() {
  cat <<-DOC
	Usage: freq=<high|low|medium> $0 <options>
	Options:
	--clean: clean the result before each test.
	-f | --force: aliases for --clean
	-v: increase verbosity level (may be used several times)
DOC
}

while [ $# -ge 1 ] ; do
  case "$1" in
    -h | --help) help ; exit 0 ;;
    -f | --force | --clean ) clean=yes ; shift ;;
    -v ) verbosity+=" $1" ; shift ;;
    *) echo "ERROR: unknown parameter $1" ; exit 2 ;;
  esac
done

#===============================================================================
# Probably nothing to change in this section:
#-------------------------------------------------------------------------------
# needed for the 'column' command:
if [ "$(which column)" = "" ] ; then
  sudo apt-get install bsdmainutils
fi

# check if 'tis-analyzer' is installed:
if [ -z "$(which tis-analyzer)" ] ; then
  echo "tis-analyzer not found: you need it to run the analysis."
  exit 1
fi

# load xunit functions:
kit_tools="$(dirname "$(which tis-analyzer)")/../kit-tools"
source "$kit_tools/tis-xunit.sh"

# to check if Jenkinsfile is compatible with kit-tools' one.
check_Jenkinsfile() {
  local name=Jenkinsfile
  local target=../Jenkinsfile
  local subst=../Jenkinsfile.sed
  local template="$kit_tools/Jenkinsfile.template"
  xunit_set_classname "$classname.$name"
  if [ ! -f "$target" ] ; then
    xunit_add_failed "$name" "not found" ""
  elif [ ! -f "$template"  ] ; then
    xunit_add_failed "$name" "$template not found" ""
  elif [ ! -f "$subst"  ] ; then
    xunit_add_failed "$name" "$subst not found" ""
  else
    sed -e "1,/^pipeline/{/^pipeline/b ; d}" -f "$subst" "$template" \
      > Jenkinsfile.new
    xunit_diff "$name" Jenkinsfile.new "$target"
  fi
}

# avoid shellcheck and nounset error
freq=${freq:-high}

# initialize xunit:
xunit_verbosity=0
# shellcheck disable=SC2086
xunit_start -xunit-file "xunit.xml" $verbosity

run() {
  local target=$1
  if [ "$target" = "symbols" ] ; then
    shift
  fi
  if [ $xunit_verbosity -lt 2 ] ; then
    eval "./run.sh $*" > /dev/null
  else
    xunit_echo 2 "Run: ./run.sh $*"
    eval "./run.sh $*"
  fi
}

check_Jenkinsfile

#===============================================================================

run_test() {
  local name="$1"
  xunit_set_classname "$classname.$name"
  rm -f "$name.diff"
  run "$name"
  result=$?

  if [ $result -ne 0 ] ; then
    xunit_add_failed "$name" "failed with exit code: $result" "$output"
  else
    config_diff=$(git diff -- "$name.config_generated")
    if [ -n "$config_diff" ] ; then
      xunit_add_error "config" "differences wit git version" "$config_diff"
    elif [ -s "$name.diff" ] ; then
      xunit_add_error "$name" "not the expected results" "$(cat "$name.diff")"
    else
      xunit_add_ok "$name"
    fi
  fi
}

run_tests() {
  local names ; names=$(./run.sh -l)
  if [ -n "$clean" ] ; then
    name=symbols
    xunit_set_classname "$classname.$name"
    output="$( run "$name" -f -s )"
    result=$?
    if [ $result -ne 0 ] ; then
      xunit_add_failed "$name" "failed with exit code: $result" "$output"
    else
      # do not compare compile_commands since the order may be different.
#       cc_diff=$(git diff -w build/compile_commands.json)
#       if [ -n "$cc_diff" ] ; then
#         xunit_add_error "compile_commands" "differences" "$cc_diff"
#       else
        xunit_add_ok "$name"
#       fi
    fi
  fi

  for name in $names ; do
    run_test "$name"
  done
}

case $freq in
  high)
    run_tests
    ;;
  medium|low)
    echo "Nothing to do yet"
    ;;
  *)
    echo "Unknown value for 'freq': '$freq'"
    exit 1
    ;;
esac

#===============================================================================

xunit_finish

#===============================================================================
