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
    {:atomic_bucket, "~> 0.4"}
  ]
end
```

For bucket storage you need to start AtomicBucket server - without
it the library will not work. Add to your application:

```elixir
children = [.., AtomicBucket, ..]
```
This will once per hour clean buckets that haven't had requests in
the last 24 hours. See **Server configuration** section below for more info.

## Usage

### Fixed cost requests

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

Cache bucket reference in `:persistent_term` for better performance. Works well
for buckets with low churn. See
[:persistent_term docs](https://www.erlang.org/doc/apps/erts/persistent_term.html#content)
for more info on the tradeoffs.
```elixir
AtomicBucket.request(:mybucket, 1, 10, 3, persistent: true)
```

Reuse bucket references in long running processes for top performance.
```elixir
{:allow, _requests, bucket_ref} = AtomicBucket.request(:mybucket, 1, 10, 3)
AtomicBucket.request(:mybucket, 1, 10, 3, ref: bucket_ref)
```

### Variable cost requests.

Use `raw_request/5` macro to implement advanced features such as token "refunds"
or variable cost. It supports same options as `request/5`
```elixir
# This would be 10 req/s with 2 burst requests in a fixed cost scenario
{:allow, tokens, ref} = AtomicBucket.raw_request(:mybucket, 200, 1, 100)

# But the next request may have a different cost
AtomicBucket.raw_request(:mybucket, 200, 1, 150)

# Token "refund" is always allowed
AtomicBucket.raw_request(:mybucket, 200, 1, -100)
```

### Multi-bucket, or multiple rate limits in 1 check.

Use `multi_request/4` macro to enforce multiple rate limits at the same time, all
in a single atomic operation. This covers cases where higher short-term rates must
be allowed without making the burst instant, while enforcing lower sustained
long-term rates. It supports same options as `request/5`

The macro uses a different algorithm where rates are defined as request intervals.
It stores multiple buckets in a single 64bit atomic but has some compromises:
  - rates resulting in fractional intervals are not supported
  - some combinations of rates can exceed maximum storage capacity

If a combination of rates exceeds capacity limit, one could try to
increase greatest common divisor (GCD) of the intervals. The smaller
the GCD value, the higher is the likelihood of exceeding the limit.
Another way to reduce the required capacity is to decrease the bursts.

For a fractional interval rate users can pick a nearest
non-fractional rate. For example, for "3 per second" one could try
the following intervals:
  - 333 or 334 if accuracy is important
  - 330 for better GCD
  - 300 for much better GCD

Note that because each request consumes from all buckets, for the multi-bucket
to work lower rates must have higher bursts - otherwise they kick in too soon.

Passing literal values for the arguments is important here, as this rate limit 
mode has more work to do and big chunk of it can be moved to compile-time.
The easiest way to ensure literals is to prepare the values in module attributes.

```elixir
# Allows 2 instant requests,
# then ~ 3 requests per second for another 5 requests,
# then ~ 1 request every 3s for another 23 requests,
# and finally when all buckets are empty the sustained rate is ~ 1 request per
# minute.
@sub_buckets %{
  second: {330, 2},
  minute: {3_000, 7},
  hour: {60_000, 30}
}
```

You can do a simple check:
```elixir
case AtomicBucket.multi_request(:mybucket, @sub_buckets) do
  {:allow, _bucket_ref} ->
    # Each bucket loses some tokens and the request is allowed.

  {:deny, _bucket_ref} ->
    # All buckets keep their tokens, the request is denied.
end
```

Or pass `details: true` if you actually need result of each bucket. This is
an opt-in feature, because it has significant cost.

```elixir
case AtomicBucket.multi_request(:mybucket, @sub_buckets, 1, details: true) do
  {:allow, requests, _bucket_ref} ->
    # Remaining requests of each bucket are returned.
    %{hour: 29, minute: 6, second: 1} = requests

  {:deny, results, _bucket_ref} ->
    # Each bucket has its own result similar to request/5, but the 
    # number of requests reflects the state after the call (not reduced).
    %{hour: {:allow, 21}, minute: {:deny, 1804}, second: {:allow, 2}} = results
end
```
Variable (including zero and negative) cost is supported via cost factor (CF).
To apply variable cost, use cost factor > 1 and scale up burst numbers accordingly.
CF only affects cost calculations for each request - capacity and refills are 
calculated using CF = 1.

Note that both number of remaining requests and timeout are scaled with CF,
but likely won't be very useful with CF > 1 (not that they make much sense with
variable cost anyway).

Zero and negative cost factor are special cases:
  - for zero cost number of remaining requests is calculated with CF = 1
  - for negative cost number of remaining requests is calculated with absolute CF
    of the request, i.e. if CF = -2, it will return requests available for CF = 2.

```elixir
# Initialize multi-bucket for future use, or peek inside existing multi-bucket.
{:allow, requests, _} = AtomicBucket.multi_request(:mybucket, @sub_buckets, 0)

# Refund all sub-buckets with token amounts equal to 1 request.
AtomicBucket.multi_request(:mybucket, @sub_buckets, -1)
```

### Server configuration

You can tune the server parameters for the buckets in use - by default 
it's using very conservative values picked to cover most common rates.

```elixir
# application.ex
children = [
  {AtomicBucket,
   cleanup_interval: :timer.minutes(20), max_idle_period: :timer.hours(1)}
]
```

As the server doesn't know parameters of the buckets, and stored
timestamps may lag because of lazy refills, it's better to avoid
very low values for `max_idle_period`. If in doubt, set it at least
2x the largest rate limit window for the table.

It's also a good idea to segregate the buckets using multiple servers where
each server is tuned for specific rate. This way lower rate buckets can stay
in memory for longer periods, while high rate buckets are removed much sooner.
Start servers with different tables and cleanup parameters and pass the table
option to `request/5`, `raw_request/5` and`multi_request/4`. Bucket ids are 
table-scoped and don't have to be globally unique.

## Caveats

The library makes no effort to ensure that bucket parameters remain
stable across calls: the parameters are not stored at all! Using same bucket
with different parameters will result in silent bugs. This also applies to 
mixing `request/5`, `raw_request/5` and `multi_request/4` - it must be
avoided.

## Benchmarks

The library provides a comprehensive benchmark suite measuring series of rate
limit checks with different parameters and bucket sizes.
See BENCHMARKING.md for more info.

## License

Copyright 2026 Andrey Tretyakov  
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
