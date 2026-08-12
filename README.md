# Atomic Bucket

<img align="left"  style="margin-right:16px;" src="https://github.com/a3kov/atomic_bucket/raw/main/assets/readme_logo.png">

Fast single node rate limiter implementing Token Bucket algorithm.
The goal is to provide dependable solution that JustWorks™ with a 
focus on performance, correctness and ease of use. Bucket data is
stored using `:atomics` module. Bucket references are stored in
ETS and optionally cached as persistent terms.

<div style="clear: both"></div><br>

## Features

 - lock-free and race-free with compare-and-swap operations

 - BlazingFast™ performance, see benchmarks section. Req/s go brrrrrr

 - monotonic timer for correct calculations

 - millisecond tick supporting wider range of parameters and preventing request starvation

 - automatic calculation of bucket parameters based on target rate and burst size
  (for fixed cost requests)

 - handy timeouts for retries

 - support for token "refunds" and variable cost requests

 - compile-time validation of arguments when possible

## Installation

Add it to your list of dependencies in `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:atomic_bucket, "~> 0.2"}
  ]
end
```

You must start AtomicBucket server for each bucket table you want to use - without
it the library will not work. Add to your application:

```elixir
children = [.., AtomicBucket, ..]
```
This will once per hour clean buckets that haven't had requests in
the last 24 hours. See `start_link/1` for info about available options.

## Usage

For simple cases where requests have fixed cost use `request/5` macro with desired
rate and burst parameters. When possible, call the macro with literal arguments
for better performance and compile-time validation. Module attributes are fine too.

```elixir
require AtomicBucket

# Averate rate: 10 reqs/s with 3 burst requests. 
case AtomicBucket.request(:mybucket, 1, 10, 3) do
  {:allow, count, _ref} ->
    # Request is allowed. May immediately attempt to make additional
    # <count> calls.
  {:deny, timeout, _ref} ->
    # Request is denied. The bucket may have enough tokens in <timeout>
    # milliseconds.
end
```

Bucket id can be any term.
```elixir
AtomicBucket.request({:client, ip_addr}, 1, 10, 3)
```

Cache bucket reference in `:persistent_term` for better performance.
Good fit for buckets with low churn. Best for fixed buckets like per-user-id
rate limits. See [:persistent_term docs](https://www.erlang.org/doc/apps/erts/persistent_term.html#content)
for more info on the tradeoffs.
```elixir
AtomicBucket.request(:mybucket, 1, 10, 3, persistent: true)
```

Reuse bucket references in long running processes for top performance.
```elixir
{:allow, _requests, bucket_ref} = AtomicBucket.request(:mybucket, 1, 10, 3)
AtomicBucket.request(:mybucket, 1, 10, 3, ref: bucket_ref)
```

Use `raw_request/5` macro to implement advanced features such as token "refunds"
or variable cost. It supports same options as `request/5`
```elixir
# This would be 10 req/s with 2 burst requests in fixed cost scenario
{:allow, tokens, ref} = AtomicBucket.raw_request(:mybucket, 200, 1, 100)
# But the next request may have a different cost
AtomicBucket.raw_request(:mybucket, 200, 1, 150)
# Token "refund" is always allowed
AtomicBucket.raw_request(:mybucket, 200, 1, -100)
```

To implement different retention policies start multiple servers and
use the table option of `request/5` and `raw_request/5`. Bucket ids are
table-scoped and don't have to be globally unique.

## Caveats

The library is optimized for common cases where rate limiters are used.
Extremely slow/fast rates and/or huge bursts may exceed the bucket storage
limits (64 bits). In practice, most people wouldn't need these extreme
parameters.

The library makes no effort to ensure that bucket parameters remain
stable across calls: the parameters are not stored at all! Using same bucket
with different parameters will result in silent bugs. This also applies to 
mixing `request/5` and `raw_request/5` - it must be avoided. No guarantee
of future compatibility of the two is provided.

## Benchmarks

The library provides a comprehensive benchmark measuring series of rate
limit checks with different parameters and bucket sizes.
See BENCHMARKING.md for more info.

## License

Copyright 2026 Andrey Tretyakov  
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
