#!/bin/bash

this_dir=$(dirname "$0")
root_dir=$(realpath "$this_dir/..")

verbose=1
do_clean=0
do_cc=0
do_symbols=0
do_prepare=0
do_run=0
do_filter=1
do_diff=1
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
-r      run the analysis even if the results exist already.
        The default is to run the analysis only if needed.
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
    -r) do_run=1 ; shift ;;
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
  rm -f Jenkinsfile.new xunit.xml

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

for name in $test_names ; do
  config="$name.config"
  echo "Process $name"

  #-----------------------------------------------------------------------------
  # Step 3a: generate the test.config_generated file from test.config

  if [[ $do_prepare -ne 0 || ! -f ${config}_generated ]] ; then
    echo -n "  prepare..."
    out=$(TIS_ADVANCED_FLOAT=1 tis-prepare --no-color tis-config "$config" \
      -- --interpreter)
    ok='Successfully completed'
    if [[ ! ( "$out" =~ $ok ) ]] ; then
      echo "Failed to compute ${config}_generated"
      exit 1
    fi
    echo "ok."
    rm -f "$name.log"
  fi

  #-----------------------------------------------------------------------------
  # Step 3b: run the analysis

  if [[ $do_run -ne 0 || ! -f "$name.state" || ! -f "$name.log" ]]; then
    echo -n "  analyze..."
    TIS_ADVANCED_FLOAT=1 tis-analyzer --interpreter \
      -tis-config-load ../tis.config -tis-config-select-by-name "$name" \
      -save "$name.state" -info-csv-all "$name" > "$name.log"
    echo "ok."
    rm -f "$name.res"
  fi

  #-----------------------------------------------------------------------------
  # Step 3c: filter the results to keep only the 'stdout' test output
  #          TODO: it would be better to have -val-stdout (see TRUS-2101)

  if [[ $do_filter -ne 0 || ! -f "$name.res" ]] ; then
    echo -n "  filter..."
    awk -f <(cat - <<-'END'
	/^\[value]/ { next; }
	/^\[kernel]/ { next; }
	/^\[tis-mkfs]/ { next; }
	/^\[info]/ { next; }
	/Too many arguments/,/ *main$/ { next; }
	/but format indicates/,/ *main$/ { next; }
	/register_new_file_in_dirent_niy/,/ *main$/ { next; }
	/initialization of volatile variable/ { next; }
	/integer overflow/ { next; }
	/overflow or underflow/ { next; }
	/invalid return value from json_c_visit/ {
           /* this is printed on stderr so not in .expected */
           next ;
           }
	/\[time]/ { printf "\n"; exit}
	/^$/ { c++ ; next; }
	{ if (c == 0) printf "\n";
          if (c >= 2) {
            for ( ; c >= 2; c -= 2) printf "\n";
            if (c == 1) printf "\n";
          }
          c = 0; printf ("%s", $0);
        }
END
    ) < "$name.log" > "$name.res"
    echo "ok."
    rm -f "$name.diff"
  fi

  #-----------------------------------------------------------------------------
  # Step 3d: compare the filtered results to the expected ones.

  if [[ $do_diff -ne 0 || ! -f "$name.diff" ]] ; then
    echo -n "  diff..."
    if [ -f "$name.todo" ] ; then
      # some differences with the expected file to be fixed
      oracle="$name.todo"
    elif [ -f "$name.oracle" ] ; then
      # some differences with the expected file but they are acceptable
      oracle="$name.oracle"
    else
      oracle="../tests/$name.expected"
    fi
    if diff "$oracle" "$name.res" > "$name.diff" ; then
      echo "ok"
    else
      echo "KO."
      echo "    See with: diff $oracle $name.res"
    fi
  fi
done
#-------------------------------------------------------------------------------
