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
        test_run_multi_r="$((test_run $1 && echo 0) || echo 1)"
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
test_cache_util_check_lines() {
    test_log "test_cache_util_check_lines $*"
    cache_file_lines="$(wc -l $1 | awk '{print $1}')"
    [ "$cache_file_lines" = $2 ]
}

test_cache_scenario() {
    cache_file="$(mktemp)"

    # no keys yet
    test_cache_util_get_failure "key1" "$cache_file"
    # set key1
    cache_set "key1" "value1" 300 "$cache_file"
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1"
    # set key2
    cache_set "key2" "value2" 300 "$cache_file"
    # update key1
    cache_set "key1" "value1_2" 300 "$cache_file"
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1_2"
    # get key2
    test_cache_util_get_success "key2" "$cache_file" "value2"
    # check file lines
    test_cache_util_check_lines "$cache_file" 3
    # try vacuum
    cache_vacuum "$cache_file"
    # check file lines
    test_cache_util_check_lines "$cache_file" 2
    # get key1
    test_cache_util_get_success "key1" "$cache_file" "value1_2"
    # get key2
    test_cache_util_get_success "key2" "$cache_file" "value2"
    # set key3 with ttl 2 second
    cache_set "key3" "value3" 2 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3"
    # expire key3
    sleep 3
    test_cache_util_get_failure "key3" "$cache_file"
    # update key3
    cache_set "key3" "value3_2" 300 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3_2"
    # update key3 with ttl 2 second
    cache_set "key3" "value3_3" 2 "$cache_file"
    # get key3
    test_cache_util_get_success "key3" "$cache_file" "value3_3"
    # expire key3
    sleep 3
    test_cache_util_get_failure "key3" "$cache_file"
    # check file lines
    test_cache_util_check_lines "$cache_file" 5
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
    test_log "test_cache_util_function_call $*"
    test_cache_util_function_call_key="$1"
    test_cache_util_function_call_ttl="$2"
    test_cache_util_function_call_count="$3"

    test_cache_util_function_call_got="$(cache_function test_cache_function_function "$test_cache_util_function_call_key" "$test_cache_util_function_call_ttl" "$test_cache_function_cache_dir")"

    [ "$test_cache_util_function_call_got" = "$test_cache_util_function_call_key" ] &&\
        test_cache_util_function_function_called "$test_cache_util_function_call_count"
}

test_cache_function() {
    test_cache_util_function_call "key1" 300 1
    test_cache_util_function_call "key1" 300 1
    test_cache_util_function_call "key2" 300 2
    test_cache_util_function_call "key3" 2 3
    test_cache_util_function_call "key3" 2 3
    sleep 3
    test_cache_util_function_call "key3" 300 4
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
        ! cache_function test_cache_function_ret_function "$1" 300 "$test_cache_function_cache_dir" > /dev/null
        test_cache_function_ret_function_called "$2"
    }

    test_cache_function_assert_failure "key1" 1
    test_cache_function_assert_failure "key1" 2

    test_cache_function_ret_function() {
        test_cache_util_incr_count "$test_cache_function_ret_function_call_count_file"
        echo "$1"
    }

    test_cache_function_assert_success "key1" 3
    test_cache_function_assert_success "key1" 3
    test_cache_function_assert_success "key2" 4
}

test_cache_coded() {
    export CACHE_ENCODE="base64"
    export CACHE_DECODE="base64 -d"

    test_cache_scenario

    export CACHE_ENCODE=""
    export CACHE_DECODE=""
}

set -e
test_run_multi "test_cache_scenario" \
               "test_cache_function" \
               "test_cache_function_ret" \
               "test_cache_coded"
