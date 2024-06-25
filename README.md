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

## Function caches

``` shell
. ./cache.sh
add1() {
  sleep 1
  expr 1 + $1
}
cache_function add1 1 # take 1 second to get 2
cache_function add1 1 # get 2 instantly
```

## Function IO caches

``` shell
. ./cache.sh
test_rev() {
  sleep 1
  rev
}
echo hoge | cache_function_io test_rev # egoh, take 1 second
echo hoge | cache_function_io test_rev # egoh, instantly
```
