#!/bin/bash

this_dir=$(dirname "$0")
root_dir=$(realpath "$this_dir/..")

verbose=1
do_clean=0
do_cc=0
do_symbols=0
do_prepare=0
test_names=""

usage() {
  cat <<END
Usage: $0 [options] [test1 [test2 ...]]

When starting from scratch:
  - build the compile_command.json file
  - generate the symbol table
  - and for each test (given as arguments, or all the tests by default):
    - generate the configuration
    - run the analysis
    - compare the results with the expected results.

When some files already exist, only the missing ones (and dependencies)
are computed, unless some options are used to force the re-computation.

Options:
-f      clean everything to restart from scratch.
-h      print this hest and exit.
-l      print the list of the test names and exit.
-p      generate the configuration files even if they exist already.
        The default is to generate them only if needed.
-q      set the verbosity to 0 (quiet).
-s      build the symbol table and exit.
-v      increase the verbosity.
END
}

all_tests=( "$root_dir"/tests/*.expected )
all_tests=( ${all_tests[@]/.expected} )
all_tests=( ${all_tests[@]##*/} )

while [[ $# -gt 0 ]] ; do
  case "$1" in
    -f) do_clean=1 ; shift ;;
    -h) usage ; exit 0 ;;
    -l) echo "${all_tests[*]}" ; exit 0 ;;
    -p) do_prepare=1 ; shift ;;
    -q) verbose=0; shift ;;
    -s) do_symbols=1; shift ;;
    -v) verbose=$(( verbose + 1 )) ; shift ;;
    *)
      name="$1"
      if [ -f "$name.config" ] ; then
        test_names+=" $name"
        shift
      else
        echo "ERROR: file not found $name.config"
        exit 1
      fi
      ;;
  esac
done
# if no test is specified on the command line, take all of them:
if [ -z "$test_names" ] ; then
  test_names="${all_tests[*]}"
fi

run_cmd() {
  local cmd="$*"
  if [ $verbose -le 1 ] ; then cmd+=" > /dev/null 2>&1 " ; fi
  if [ $verbose -ge 1 ] ; then echo "Run: $cmd" ; fi
  eval "$cmd"
}

#===============================================================================
# Step 0: clean everything to restart from scratch
#-------------------------------------------------------------------------------

if [[ $do_clean -ne 0 ]] ; then
  if [ -d build ] ; then
    pushd build
    run_cmd tis-prepare clean
    popd
    rm -rf build
  fi
  rm -f ./*.state ./*.log ./*.csv ./*.res ./*.diff
  rm -f ./*.config_generated.json
  rm -f __vfs-*.[ch]

  git_clean=$(git clean -nxd)
  if [ -n "$git_clean" ] ; then
    echo "Warning: some files were not cleaned:"
    echo "$git_clean"
  fi
fi

#-------------------------------------------------------------------------------
# Step 1: generate the `compile_commands.json` file
#-------------------------------------------------------------------------------

if [[ $do_cc -ne 0 || ! -f build/compile_commands.json ]] ; then
  rm -rf build && mkdir build && pushd build
  run_cmd "cmake ../.. -DCMAKE_EXPORT_COMPILE_COMMANDS=On"
  sed -i config.h -e '/HAVE_XLOCALE_H/d' -e '/HAVE_USELOCALE/d'
  run_cmd make
  # make USE_VALGRIND=0 test

  # To be able to use the `compile_commands.json` elsewhere (on GitHub for ex.)
  # the absolute paths have to be transformed into relative ones:
  sed -i compile_commands.json -e "s=$root_dir=../..=g" \
                               -e '/"directory"/s/.*/  "directory": ".",/'

  popd
fi

#-------------------------------------------------------------------------------
# Step 2: symbol table
#-------------------------------------------------------------------------------

if [[ $do_symbols -ne 0 || ! -f build/tis_symbols.tbl ]] ; then
  run_cmd tis-prepare all-symbol-table build/compile_commands.json
  if [ $do_symbols -ne 0 ] ; then
    exit 0
  fi
  echo "Clean all the test.config_generated files"
  for name in $test_names ; do
    rm -f "$name.config_generated"
  done
fi

#-------------------------------------------------------------------------------
# Step 3: process the tests
#-------------------------------------------------------------------------------

rm -f my_tis.config
echo "[" >> my_tis.config
fst_test=1

for name in $test_names ; do
  config="$name.config"
  echo "Process $name"

  # my_tis.config
  if [[ $fst_test -ne 1 ]] ; then
    echo "    }," >> my_tis.config
  fi
  fst_test=0
  echo "    {" >> my_tis.config
  echo "        \"name\": \"$name\"," >> my_tis.config
  # echo "        \"include\": \"tis/${config}_generated\"" >> my_tis.config

  #-----------------------------------------------------------------------------
  # Step 3a: generate the test.config_generated file from test.config

  if [[ $do_prepare -ne 0 || ! -f ${config}_generated ]] ; then
    echo -n "  prepare..."
    out=$(TIS_ADVANCED_FLOAT=1 tis-prepare --no-color tis-config "$config" \
      -- --interpreter)
    ok='Successfully completed'
    if [[ ! ( "$out" =~ $ok ) ]] ; then
      echo " Failed to compute ${config}_generated"
      exit 1
    fi
    echo " ok."
    rm -f "$name.log"
  fi

  # Skip first two lines.
  # Skip last two lines.
  # Remove one '../' in each line.
  # Replace all 'build' by 'tis/build'
  cat ${config}_generated | tail -n +3 | head -n -2 | sed 's/\.\.\///' | sed 's/build/tis\/build/' >> my_tis.config

done

echo "    }" >> my_tis.config
echo "]" >> my_tis.config

#-------------------------------------------------------------------------------

# Remove stuff useless for TiS-CI
clean_stuff() {
  rm -f ./*.c_config.json
  rm -f ./*.c_functions.csv
  rm -f ./*.c_time.txt
  rm -f ./*.c_variables.csv
}

pushd ..
clean_stuff # /
pushd apps
clean_stuff # /apps
popd
pushd tests # /tests
clean_stuff
popd
popd

rm -f ./build/tis_symbols.tbl
rm -f ./*.config_generated.json
rm -f __vfs-*.[ch]
