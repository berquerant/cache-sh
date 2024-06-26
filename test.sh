#!/bin/bash

test_log() {
    echo "[test] $*" > /dev/stderr
}

test_run() {
    test_log "Start $1 ----------"
    "$1"
    test_run_ret=$?
    test_log "End $1 ------------"
    return $test_run_ret
}

test_run_multi() {
    test_run_multi_result="$(mktemp)"

    test_run_multi_ret=0
    while [ -n "$1" ] ; do
        test_run_multi_r="$((test_run $1 > /dev/stderr && echo 0) || echo 1)"
        if [ $test_run_multi_r -gt 0 ] ; then
            test_run_multi_ret=$test_run_multi_r
        fi
        echo "$1 ${test_run_multi_r}" >> "$test_run_multi_result"
        shift
    done

    test_log "----------"
    cat "$test_run_multi_result" > /dev/stderr
    return $test_run_multi_ret
}

thisd="$(cd $(dirname $0); pwd)"
. "${thisd}/cache.sh"

test_cache_util_get_failure() {
    test_log "test_cache_util_get_failure $*"
    ! cache_get "$1" "$2" > /dev/null
}
test_cache_util_get_success() {
    test_log "test_cache_util_get_success $*"
    if ! cache_get "$1" "$2" > /dev/null ; then
        return 1
    fi
    cache_util_get_value="$(cache_get $1 $2)"
    [ "$cache_util_get_value" = "$3" ]
}

test_cache_scenario() {
    cache_file="$(mktemp)"

    # no keys yet
    test_cache_util_get_failure "key1" "$cache_file" || return 1
    # set key1
    cache_set "key1" "value1" 300 "$cache_file"
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1" || return 1
    # set key2
    cache_set "key2" "value2" 300 "$cache_file"
    # update key1
    cache_set "key1" "value1_2" 300 "$cache_file"
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1_2" || return 1
    # get key2
    test_cache_util_get_success "key2" "$cache_file" "value2" || return 1
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1_2" || return 1
    # get key2
    test_cache_util_get_success "key2" "$cache_file" "value2" || return 1
    # set key3 with ttl 2 second
    cache_set "key3" "value3" 2 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3" || return 1
    # expire key3
    sleep 3
    test_cache_util_get_failure "key3" "$cache_file" || return 1
    # update key3
    cache_set "key3" "value3_2" 300 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3_2" || return 1
    # update key3 with ttl 2 second
    cache_set "key3" "value3_3" 2 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3_3" || return 1
    # expire key3
    sleep 3
    test_cache_util_get_failure "key3" "$cache_file" || return 1
}

test_cache_util_get_count() {
    test_cache_util_get_count_c=0
    if [ -s "$1" ] ; then
        test_cache_util_get_count_c="$(cat "$1")"
    fi
    echo "$test_cache_util_get_count_c"
}

test_cache_util_incr_count() {
    test_cache_util_incr_count_c="$(test_cache_util_get_count "$1")"
    test_cache_util_incr_count_c="$(expr $test_cache_util_incr_count_c + 1)"
    echo "$test_cache_util_incr_count_c" > "$1"
}

test_cache_util_called_count() {
    [ "$(test_cache_util_get_count "$1")" = "$2" ]
}

test_cache_function_function_call_count_file="$(mktemp)"

test_cache_function_function() {
    test_cache_util_incr_count "$test_cache_function_function_call_count_file"
    echo "$1"
}

test_cache_util_function_function_called() {
    test_cache_util_called_count "$test_cache_function_function_call_count_file" "$1"
}

test_cache_function_cache_dir="$(mktemp -d)"

test_cache_util_function_call() {
    test_log "test_cache_util_function_call $* CACHE_FUNCTION_OVERWRITE=${CACHE_FUNCTION_OVERWRITE}"
    test_cache_util_function_call_key="$1"
    test_cache_util_function_call_ttl="$2"
    test_cache_util_function_call_count="$3"

    test_cache_util_function_call_got="$(cache_function test_cache_function_function "$test_cache_util_function_call_key" "$test_cache_util_function_call_ttl" "$test_cache_function_cache_dir")"

    [ "$test_cache_util_function_call_got" = "$test_cache_util_function_call_key" ] &&\
        test_cache_util_function_function_called "$test_cache_util_function_call_count"
}

test_cache_function() {
    test_cache_util_function_call "key1" 300 1 || return 1
    test_cache_util_function_call "key1" 300 1 || return 1
    test_cache_util_function_call "key2" 300 2 || return 1
    test_cache_util_function_call "key3" 2 3 || return 1
    test_cache_util_function_call "key3" 2 3 || return 1
    sleep 3
    test_cache_util_function_call "key3" 300 4 || return 1
    test_cache_util_function_call "key3" 300 4 || return 1
    CACHE_FUNCTION_OVERWRITE=1 test_cache_util_function_call "key3" 300 5 || return 1
    CACHE_FUNCTION_OVERWRITE=1 test_cache_util_function_call "key3" 300 6 || return 1
    test_cache_util_function_call "key3" 300 6 || return 1
}

test_cache_function_ret() {
    test_cache_function_ret_function_call_count_file="$(mktemp)"
    test_cache_function_ret_function_called() {
        test_cache_util_called_count "$test_cache_function_ret_function_call_count_file" "$1"
    }
    test_cache_function_ret_function() {
        test_cache_util_incr_count "$test_cache_function_ret_function_call_count_file"
    }
    test_cache_function_assert_success() {
        test_log "test_cache_function_assert_success $*"
        test_cache_function_assert_got="$(cache_function test_cache_function_ret_function "$1" 300 "$test_cache_function_cache_dir")"

        [ "$1" = "$test_cache_function_assert_got" ] &&\
            test_cache_function_ret_function_called "$2"
    }
    test_cache_function_assert_failure() {
        test_log "test_cache_function_assert_failure $*"
        test_cache_function_assert_failure_ret=0
        cache_function test_cache_function_ret_function "$1" 300 "$test_cache_function_cache_dir" > /dev/null || test_cache_function_assert_failure_ret=$?
        test_cache_function_ret_function_called "$2" &&\
            [ "$test_cache_function_assert_failure_ret" = "$3" ]
    }

    test_cache_function_assert_failure "key1" 1 1 || return 1
    test_cache_function_assert_failure "key1" 2 1 || return 1

    test_cache_function_ret_function() {
        test_cache_util_incr_count "$test_cache_function_ret_function_call_count_file"
        echo "$1"
    }

    test_cache_function_assert_success "key1" 3 || return 1
    test_cache_function_assert_success "key1" 3 || return 1
    test_cache_function_assert_success "key2" 4 || return 1

    test_cache_function_ret_function() {
        test_cache_util_incr_count "$test_cache_function_ret_function_call_count_file"
        echo "$1"
        return 1
    }

    test_cache_function_assert_failure "key3" 5 2 || return 1
}

test_cache_function_io() {
    test_cache_function_io_call_count_file="$(mktemp)"
    test_cache_function_io_function_called() {
        test_cache_util_called_count "$test_cache_function_io_call_count_file" "$1"
    }
    test_cache_function_io_function() {
        test_cache_util_incr_count "$test_cache_function_io_call_count_file"
        grep "hit"
        echo "STDERR:$(test_cache_util_get_count "$test_cache_function_io_call_count_file")" > /dev/stderr
    }
    test_cache_function_io_function_dir="$(mktemp -d)"
    test_cache_function_io_assert_success_want="$(mktemp)"
    test_cache_function_io_assert_success() {
        test_log "test_cache_function_io_assert_success $*"
        test_cache_function_io_assert_success_got="$(mktemp)"

        cache_function_io test_cache_function_io_function "$1" "$test_cache_function_io_function_dir" > "$test_cache_function_io_assert_success_got"
        test_cache_function_io_function_called "$2" &&\
            diff "$test_cache_function_io_assert_success_want" "$test_cache_function_io_assert_success_got"
    }
    test_cache_function_io_assert_failure() {
        test_log "test_cache_function_io_assert_failure $*"
        test_cache_function_io_assert_failure_want="$1"
        test_cache_function_io_assert_failure_got=0
        cache_function_io test_cache_function_io_function 300 "$test_cache_function_io_function_dir" || test_cache_function_io_assert_failure_got=$?
        [ "$test_cache_function_io_assert_failure_want" = "$test_cache_function_io_assert_failure_got" ]
    }

    test_cache_function_io_input1="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_input1"
hit
miss
hit
EOS
    test_cache_function_io_want1="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_want1"
hit
hit
EOS
    test_cache_function_io_input2="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_input2"
hit
miss
hit2
EOS
    test_cache_function_io_want2="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_want2"
hit
hit2
EOS

    test_cache_function_io_input3="$(mktemp)"
    echo "failure" > "$test_cache_function_io_input3"

    cat "$test_cache_function_io_want1" > "$test_cache_function_io_assert_success_want"
    test_cache_function_io_assert_success 300 1 < "$test_cache_function_io_input1" || return 1
    test_cache_function_io_assert_success 300 1 < "$test_cache_function_io_input1" || return 1
    CACHE_FUNCTION_OVERWRITE=1 test_cache_function_io_assert_success 300 2 < "$test_cache_function_io_input1" || return 1
    cat "$test_cache_function_io_want2" > "$test_cache_function_io_assert_success_want"
    test_cache_function_io_assert_success 2 3 < "$test_cache_function_io_input2" || return 1
    sleep 3
    test_cache_function_io_assert_success 2 4 < "$test_cache_function_io_input2" || return 1

    test_cache_function_io_function() {
        test_cache_util_incr_count "$test_cache_function_io_call_count_file"
    }
    test_cache_function_io_assert_failure 1 < "$test_cache_function_io_input3" || return 1
    test_cache_function_io_function() {
        test_cache_util_incr_count "$test_cache_function_io_call_count_file"
        echo "error"
        return 1
    }
    test_cache_function_io_assert_failure 2 < "$test_cache_function_io_input3" || return 1
}

test_cache_function_args() {
    export CACHE_DIR="$(mktemp -d)"
    test_cache_function_args_function_call_count_file="$(mktemp)"
    test_cache_function_args_function_called() {
        test_cache_util_called_count "$test_cache_function_args_function_call_count_file" "$1"
    }
    test_cache_function_args_function() {
        test_cache_util_incr_count "$test_cache_function_args_function_call_count_file"
        echo "$*"
    }
    test_cache_function_args_assert_success() {
        test_log "test_cache_function_args_assert_success $*"
        test_cache_function_args_assert_success_want_called="$1"
        shift
        test_cache_function_args_assert_success_got="$(cache_function_args test_cache_function_args_function "$@")"
        [ "$test_cache_function_args_assert_success_got" = "$*" ] &&\
            test_cache_function_args_function_called "$test_cache_function_args_assert_success_want_called"
    }
    test_cache_function_args_assert_failure() {
        test_log "test_cache_function_args_assert_failure $*"
        test_cache_function_args_assert_failure_want_called="$1"
        test_cache_function_args_assert_failure_want_ret="$2"
        shift 2
        test_cache_function_args_assert_failure_ret=0
        cache_function_args test_cache_function_args_function "$@" > /dev/null || test_cache_function_args_assert_failure_ret=$?
        test_cache_function_args_function_called "$test_cache_function_args_assert_failure_want_called" &&\
            [ "$test_cache_function_args_assert_failure_want_ret" = "$test_cache_function_args_assert_failure_ret" ]
    }

    test_cache_function_args_assert_success 1 k1 || return 1
    test_cache_function_args_assert_success 1 k1 || return 1
    test_cache_function_args_assert_success 2 k2 || return 1
    test_cache_function_args_assert_success 3 k1 k2 || return 1
    test_cache_function_args_assert_success 3 k1 k2 || return 1
    CACHE_FUNCTION_OVERWRITE=1 test_cache_function_args_assert_success 4 k1 k2 || return 1
    test_cache_function_args_assert_success 4 k1 k2 || return 1
    test_cache_function_args_assert_success 4 k1 || return 1

    test_cache_function_args_function() {
        test_cache_util_incr_count "$test_cache_function_args_function_call_count_file"
    }

    test_cache_function_args_assert_failure 5 1 k11 || return 1
    test_cache_function_args_assert_failure 6 1 k11 || return 1
    test_cache_function_args_assert_failure 7 1 k11 k12 || return 1

    test_cache_function_args_function() {
        test_cache_util_incr_count "$test_cache_function_args_function_call_count_file"
        echo "$*"
        return 1
    }

    test_cache_function_args_assert_failure 8 2 k111 || return 1
}

test_cache_function_io_args() {
    export CACHE_DIR="$(mktemp -d)"
    test_cache_function_io_args_call_count_file="$(mktemp)"
    test_cache_function_io_args_function_called() {
        test_cache_util_called_count "$test_cache_function_io_args_call_count_file" "$1"
    }
    test_cache_function_io_args_function() {
        test_cache_util_incr_count "$test_cache_function_io_args_call_count_file"
        grep "hit"
        echo "STDERR:$(test_cache_util_get_count "$test_cache_function_io_args_call_count_file")" > /dev/stderr
    }

    test_cache_function_io_args_assert_success_want="$(mktemp)"
    test_cache_function_io_args_assert_success() {
        test_log "test_cache_function_io_args_assert_success $*"
        test_cache_function_io_args_assert_success_want_called="$1"
        shift
        test_cache_function_io_args_assert_success_got="$(mktemp)"

        cache_function_io_args test_cache_function_io_args_function "$@" > "$test_cache_function_io_args_assert_success_got"
        test_cache_function_io_args_function_called "$test_cache_function_io_args_assert_success_want_called" &&\
            diff "$test_cache_function_io_args_assert_success_want" "$test_cache_function_io_args_assert_success_got"
    }
    test_cache_function_io_args_assert_failure() {
        test_log "test_cache_function_io_args_assert_failure $*"
        test_cache_function_io_args_assert_failure_want_called="$1"
        test_cache_function_io_args_assert_failure_want_ret="$2"
        shift 2
        test_cache_function_io_args_assert_failure_got_ret="$(mktemp)"
        echo 0 > "$test_cache_function_io_args_assert_failure_got_ret"
        cache_function_io_args test_cache_function_io_args_function "$@" > /dev/null || echo $? > "$test_cache_function_io_args_assert_failure_got_ret"
        [ "$test_cache_function_io_args_assert_failure_want_ret" = "$(cat "$test_cache_function_io_args_assert_failure_got_ret")" ] &&\
            test_cache_function_io_args_function_called "$test_cache_function_io_args_assert_failure_want_called"
    }

    test_cache_function_io_args_input1="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_args_input1"
hit
miss
hit
EOS
    test_cache_function_io_args_want1="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_args_want1"
hit
hit
EOS
    test_cache_function_io_args_input2="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_args_input2"
hit
miss
hit2
EOS
    test_cache_function_io_args_want2="$(mktemp)"
    cat - <<EOS > "$test_cache_function_io_args_want2"
hit
hit2
EOS

    test_cache_function_io_args_input3="$(mktemp)"
    echo "failure" > "$test_cache_function_io_args_input3"

    cat "$test_cache_function_io_args_want1" > "$test_cache_function_io_args_assert_success_want"
    test_cache_function_io_args_assert_success 1 k1 < "$test_cache_function_io_args_input1" || return 1
    test_cache_function_io_args_assert_success 1 k1 < "$test_cache_function_io_args_input1" || return 1
    CACHE_FUNCTION_OVERWRITE=1 test_cache_function_io_args_assert_success 2 k1 < "$test_cache_function_io_args_input1"
    test_cache_function_io_args_assert_success 3 k2 < "$test_cache_function_io_args_input1" || return 1
    test_cache_function_io_args_assert_success 4 k1 k2 < "$test_cache_function_io_args_input1" || return 1
    cat "$test_cache_function_io_args_want2" > "$test_cache_function_io_args_assert_success_want"
    test_cache_function_io_args_assert_success 5 k1 k2 < "$test_cache_function_io_args_input2" || return 1
    test_cache_function_io_args_assert_success 5 k1 k2 < "$test_cache_function_io_args_input2" || return 1

    test_cache_function_io_args_function() {
        test_cache_util_incr_count "$test_cache_function_io_args_call_count_file"
    }
    test_cache_function_io_args_assert_failure 6 1 k11 < "$test_cache_function_io_args_input2" || return 1
    test_cache_function_io_args_assert_failure 7 1 k11 < "$test_cache_function_io_args_input2" || return 1
    test_cache_function_io_args_assert_failure 8 1 k11 < "$test_cache_function_io_args_input3" || return 1
    test_cache_function_io_args_function() {
        test_cache_util_incr_count "$test_cache_function_io_args_call_count_file"
        echo "error"
        return 1
    }
    test_cache_function_io_args_assert_failure 9 2 k111 < "$test_cache_function_io_args_input3" || return 1
}

set -e
test_run_multi test_cache_scenario \
               test_cache_function \
               test_cache_function_ret \
               test_cache_function_io \
               test_cache_function_args \
               test_cache_function_io_args
