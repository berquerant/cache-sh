# cache-sh

Provides functions for simple cashing.

# Examples

## Cache values and TTL

``` shell
. ./cache.sh
cache_set key1 value1
cache_get key1 # => value1
cache_set key2 value2 3
cache_get key2 # => value2
sleep 4
cache_get key2 # empty
```

## Cache by function argument

``` shell
. ./cache.sh
add1() {
  sleep 1
  expr 1 + $1
}
cache_function add1 1 # take 1 second to get 2
cache_function add1 1 # get 2 instantly
```

## Cache by function input

``` shell
. ./cache.sh
test_rev() {
  sleep 1
  rev
}
echo hoge | cache_function_io test_rev # egoh, take 1 second
echo hoge | cache_function_io test_rev # egoh, instantly
```

## Cache by function arguments

``` shell
. ./cache.sh
add() {
    sleep 1
    expr $(echo "$*" | sed 's/ / + /g')
}

cache_function_args add 1 2 # 3, take 1 second
cache_function_args add 1 2 # 3, instantly
cache_function_args add 1 2 3 # 6, take 1 second
```

## Cache by function arguments and input

``` shell
. ./cache.sh
concat() {
    sleep 1
    echo "$(cat -)|$*"
}

echo hoge | cache_function_io_args concat 1 2 # hoge|1 2, take 1 second
echo hoge | cache_function_io_args concat 1 2 # hoge|1 2, instantly
echo foo | cache_function_io_args concat 1 2 # foo|1 2, take 1 second
echo foo | cache_function_io_args concat 1 2 3 # foo|1 2 3, take 1 second
echo foo | cache_function_io_args concat 1 2 3 # foo|1 2 3, instantly
```
