#!/bin/bash

# Provides functions for simple cashing

# Cache line format:
# TIMESTAMP\tTTL_SECOND\tKEY\tVALUE
#
# File for cache:
# Default is cache_directory/.cache
# cache_directory is CACHE_DIR
#
# Environment variables:
#   CACHE_KV_SEP
#     Cache line separator.
#     Default is \t
#
#   CACHE_DIR
#     Diretory for cache files.
#     Default is $HOME/.cache-sh/
#
#   CACHE_TTL
#     Cache record ttl seconds.
#     Default is 300
#
#   CACHE_ENCODE
#     Command to encode cache record.
#     Default is cat -
#
#   CACHE_DECODE
#     Command to decode cache record.
#     Default is cat -

__cache_kv_sep() {
    echo "${CACHE_KV_SEP:-\t}"
}

__cache_encode() {
    if [ -n "$CACHE_ENCODE" ] ; then
        $CACHE_ENCODE
    else
        cat -
    fi
}

__cache_decode() {
    if [ -n "$CACHE_DECODE" ] ; then
        $CACHE_DECODE
    else
        cat -
    fi
}

__ensure_dir() {
    mkdir -p "$1"
    echo "$1"
}

__ensure_file() {
    mkdir -p "$(dirname "$1")"
    touch "$1"
    echo "$1"
}

__cache_root() {
    __ensure_dir "${1:-${CACHE_DIR:-$HOME/.cache-sh/}}"
}

__cache_kv_dir() {
    __ensure_dir "$(__cache_root "$1")/kv/"
}

__cache_kv_file() {
    __ensure_file "${1:-$(__cache_kv_dir)/.cache}"
}

__cache_function_dir() {
    __ensure_dir "$(__cache_root "$1")/function/"
}

__cache_ttl() {
    echo "${1:-${CACHE_TTL:-300}}"
}

__cache_timestamp_now() {
    date +%s
}

__cache_awk() {
    awk -F "$(__cache_kv_sep)" "$@"
}

__cache_echo() {
    if [ "$(uname)" = "Linux" ] ; then
        # enable interpretation of backslash escapes
        echo -e "$@"
    else
        echo "$@"
    fi
}

# Set new record
#
# $1: key
# $2: value, not empty
# $3: ttl second, optional
# $4: cache db file, optional
cache_set() {
    __cache_set_key="$1"
    __cache_set_value="$2"
    __cache_set_ttl="$(__cache_ttl "$3")"
    __cache_set_file="$(__cache_kv_file "$4")"

    if [ -z "$__cache_set_key" ] || [ -z "$__cache_set_value" ] || [ -z "$__cache_set_ttl" ] ; then
        return 1
    fi

    __cache_set_key="$(echo "$__cache_set_key" | __cache_encode)"
    __cache_set_value="$(echo "$__cache_set_value" | __cache_encode)"
    __cache_set_timestamp="$(__cache_timestamp_now)"
    __cache_set_kv_sep="$(__cache_kv_sep)"
    __cache_echo "${__cache_set_timestamp}${__cache_set_kv_sep}${__cache_set_ttl}${__cache_set_kv_sep}${__cache_set_key}${__cache_set_kv_sep}${__cache_set_value}" >> "$__cache_set_file"
}

__cache_line2key() {
    __cache_awk '{print $3}' "$@"
}

__cache_line2value() {
    __cache_awk '{print $4}' "$@"
}

__cache_get_raw() {
    __cache_get_raw_key="$1"
    __cache_get_raw_now="$2"
    __cache_get_raw_file="$3"

    # select records by key
    __cache_awk -v key="$__cache_get_raw_key" \
                '$3 == key' \
                "$__cache_get_file" |\
        # select latest record
        tail -n 1 |\
        # ignore expired record
        __cache_awk -v now="$__cache_get_raw_now" \
                    'now <= $1 + $2'
}

__cache_get() {
    __cache_get_key="$1"
    __cache_get_file="$(__cache_kv_file "$2")"

    if [ ! -f "$__cache_get_file" ] ; then
       return
    fi

    __cache_get_now="$(__cache_timestamp_now)"
    __cache_get_value="$(__cache_get_raw "$__cache_get_key" "$__cache_get_now" "$__cache_get_file")"
    if [ -z "$__cache_get_value" ] ; then
        return
    fi
    __cache_echo "$__cache_get_value"
}

# Get value by key
#
# $1: key
# $2: cache db file, optional
#
# Exit status is 1 if not found
cache_get() {
    __cache_get_key="$(echo "$1" | __cache_encode)"
    __cache_get_got="$(__cache_get "$__cache_get_key" "$2")"
    if [ -z "$__cache_get_got" ] ; then
        # empty is invalid
        return 1
    fi
    __cache_echo "$__cache_get_got" | __cache_line2value | __cache_decode
}

# Shrink db file by removing invalid records
#
# $1: cache db file, optional
cache_vacuum() {
    __cache_vaccum_file="$(__cache_kv_file "$1")"
    # collect all keys
    __cache_vaccum_keys="$(mktemp)"
    __cache_line2key "$__cache_vaccum_file" | sort -u > "$__cache_vaccum_keys"

    __cache_vaccum_tmp_file="$(mktemp)"
    while read key ; do
        __cache_vaccum_got="$(__cache_get "$key" "$__cache_vaccum_file")"
        if [ -n "$__cache_vaccum_got" ] ; then
            # collect latest values
            __cache_echo "$__cache_vaccum_got" >> "$__cache_vaccum_tmp_file"
        fi
    done < "$__cache_vaccum_keys"
    # overwrite by latest values
    mv -f "$__cache_vaccum_tmp_file" "$__cache_vaccum_file"
}

# Shrink all db files in cache directory
#
# $1: cache directory, optional
cache_vacuum_all() {
    __cache_vacuum_all_dir="$(__cache_kv_dir "$1")"
    find "$__cache_vacuum_all_dir" -type f | while read line ; do
        cache_vacuum "$line"
    done
}

# Get value from cache. If not, call the function and cache the result
#
# $1: name of function that take 1 argument
# $2: key
# $3: cache ttl, optional
# $4: cache db directory, optional
#
# Cache values into cache_dir/function_name.
# Write cache even if cache hit when CACHE_FUNCTION_OVERWRITE is not empty.
# Exit status is 1 if function do not output
cache_function() {
    __cache_function_function="$1"
    __cache_function_key="$2"
    __cache_function_ttl="$(__cache_ttl "$3")"
    __cache_function_file="$(__cache_function_dir "$4")/${__cache_function_function}"
    touch "$__cache_function_file"

    __cache_function_got=""
    if [ -z "$CACHE_FUNCTION_OVERWRITE" ] ; then
        # try to get cache
        __cache_function_got="$(cache_get "$__cache_function_key" "$__cache_function_file" || echo)"
    fi
    if [ -z "$__cache_function_got" ] ; then
        # cache miss
        __cache_function_got="$($__cache_function_function "$__cache_function_key" || echo)"
        if [ -z "$__cache_function_got" ] ; then
            # empty output is invalid
            return 1
        fi
        # cache output
        cache_set "$__cache_function_key" "$__cache_function_got" "$__cache_function_ttl" "$__cache_function_file"
    fi
    __cache_echo "$__cache_function_got"
}
