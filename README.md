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

 - multiple rate limit checks in 1 atomic operation

 - compile-time validation of arguments when possible

## Installation

Add it to your list of dependencies in `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:atomic_bucket, "~> 0.5"}
  ]
end
```

## Usage

### Fixed cost requests

For simple cases where requests have fixed cost create use `AtomicBucket.FixedCostLimiter`.

```elixir
defmodule MyFixedLimiter do
  use AtomicBucket.FixedCostLimiter
end
```

To store bucket data you need to start the server that manages buckets - without
it the rate limiter will not work.

This will once per hour clean buckets that haven't had requests in
the last 24 hours. See **Rate limiter configuration** section below for more info.

```elixir
# application.ex
children = [.., MyFixedLimiter, ..]
```

The rate limiter module now has generated API.
```elixir
defmodule CallerModule do
  require MyFixedLimiter

  # Averate rate: 10 reqs/s with 3 burst requests. 
  case MyFixedLimiter.request(:mybucket, 1, 10, 3) do
    {:allow, count, _ref} ->
      # Request is allowed. May immediately attempt to make additional
      # <count> calls.

    {:deny, timeout, _ref} ->
      # Request is denied. The bucket may have enough tokens in <timeout>
      # milliseconds.
  end
end
```

### Variable cost requests.

Create a rate limiter using `AtomicBucket.VariableCostLimiter` to implement advanced 
features such as token "refunds" or variable cost.
```elixir
defmodule MyVariableLimiter do
  use AtomicBucket.VariableCostLimiter
end

# application.ex
children = [.., MyVariableLimiter, ..]

defmodule CallerModule do
  require MyVariableLimiter

  # This would be 10 req/s with 2 burst requests in a fixed cost scenario
  {:allow, tokens, ref} = MyVariableLimiter.request(:mybucket, 200, 1, 100)

  # But the next request may have a different cost
  MyVariableLimiter.request(:mybucket, 200, 1, 150)

  # Token "refund" is always allowed
  MyVariableLimiter.request(:mybucket, 200, 1, -100)
end
```

### Multi-bucket, or multiple rate limits in 1 check.

Use `AtomicBucket.MultiRateLimiter` to create rate limiters enforcing
multiple rate limits at the same time, all in a single atomic operation.
This covers cases where higher short-term rates must be allowed without making
the whole burst instant, while enforcing lower sustained long-term rates.

This rate limiter type uses a different algorithm where rates are defined as request
intervals. It stores multiple buckets in a single 64bit atomic but has some compromises:
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

There must be no duplicate intervals inside the sub-buckets, and lower
rate buckets must have bigger bursts (otherwise they kick in too soon).


```elixir
defmodule MyMultiLimiter do
  use AtomicBucket.MultiRateLimiter
end

defmodule CallerModule do
  require MyMultiLimiter

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

  # You can do a simple check:
  case MyMultiLimiter.request(:mybucket, @sub_buckets) do
    {:allow, _bucket_ref} ->
      # Each bucket loses some tokens and the request is allowed.

    {:deny, _bucket_ref} ->
      # All buckets keep their tokens, the request is denied.
  end

  # Or use `request_details/4` if you actually need results of each bucket.
  case MyMultiLimiter.request_details(:mybucket, @sub_buckets) do
    {:allow, requests, _bucket_ref} ->
      # Remaining requests of each bucket are returned.
      %{hour: 29, minute: 6, second: 1} = requests

    {:deny, results, _bucket_ref} ->
      # Each bucket has its own result similar to `FixedCostLimiter.request/5`,
      # but the number of requests reflects the state after the call (not reduced).
      %{hour: {:allow, 21}, minute: {:deny, 1804}, second: {:allow, 2}} = results
  end
end
```

Variable (including zero and negative) cost is supported via cost factor (CF).
To apply variable cost, use CF > 1 and scale up burst numbers accordingly.
CF only affects cost calculations for each request - capacity and refills are 
calculated using CF = 1.

Note that both number of remaining requests and timeout are scaled with CF,
but likely won't be very useful with CF > 1 (not that they make much sense with
variable cost anyway).

Zero and negative CF are special cases:
  - for zero CF number of remaining requests is calculated with CF = 1
  - for negative CF number of remaining requests is calculated with absolute CF
    of the request, i.e. if CF = -2, requests use CF = 2.

```elixir
# Peek inside existing multi-bucket.
MyMultiLimiter.request_details(:mybucket, @sub_buckets, 0)

# Refund all sub-buckets with token amounts equal to 1 request.
MyMultiLimiter.request(:mybucket, @sub_buckets, -1)
```

### Common tips (apply to all types of rate limiters)

When possible, call request macros with literal arguments for better performance and
compile-time validation. Module attributes and macros that expand to literals will work
well too. This is especially important for `MultiRateLimiter` which is relatively heavy
computation-wise.

Bucket ids are scoped within its rate limiter (i.e. the ETS table) and don't have
to be globally unique. Bucket id can be any term - it can refer to a specific resource
or an external id.
```elixir
MyFixedLimiter.request({:client, ip_addr}, 1, 10, 3)
```

You can cache bucket references in `:persistent_term` for better performance. It should work
well for buckets with low churn. Ideally, it must be buckets that are never deleted (until 
the next deployment). See
[:persistent_term docs](https://www.erlang.org/doc/apps/erts/persistent_term.html#content)
for more info on the tradeoffs.

```elixir
defmodule MyLimiter do
  use AtomicBucket.VariableCostLimiter, persistent: true
end
```

For top performance you can reuse bucket references in long running processes.
```elixir
{:allow, _requests, bucket_ref} = MyFixedLimiter.request(:mybucket, 1, 10, 3)

# Store bucket_ref somewhere, or pass it around.

# This call is *much* faster than the previous one.
MyFixedLimiter.request(:mybucket, 1, 10, 3, ref: bucket_ref)
```

### Rate limiter configuration

You can tune the server parameters for each rate limiter - by default 
it's using very conservative values picked to cover most common rates.
See `__using__/1` doc of each rate limiter for more info about the options.

As the server doesn't know parameters of the buckets, and stored
timestamps may lag because of lazy refills, it's better to avoid
very low values for `max_idle_period`. If in doubt, set it at least
2x the largest rate limit window for the rate limiter.

It's also a good idea to segregate the buckets using multiple limiters where
each limiter is tuned for specific bucket type. This allows to keep lower rate
buckets in memory for longer periods, while removing high rate buckets much sooner.


```elixir
defmodule HighRateLimiter do
  use AtomicBucket.FixedCostLimiter,
    cleanup_interval: :timer.minutes(20),
    max_idle_period: :timer.hours(1)
end

defmodule LowRateLimiter do
  use AtomicBucket.FixedCostLimiter,
    cleanup_interval: :timer.hours(3),
    max_idle_period: :timer.hours(12)
end

# application.ex
children = [
  HighRateLimiter,
  LowRateLimiter
]
```

## Upgrading to 0.5.x from earlier versions.

1) Check your application supervision tree. For every AtomicBucket entry create 
corresponding rate limiting module, and move the cleanup params to the `use` call.

2) If an AtomicBucket table was used for different types of buckets (fixed, variable,
multi-rate), add a module for each bucket type.

3) If a table was used for persistent buckets, add a module having `persistent: true`.

4) Replace all AtomicBucket calls with rate limiter module calls:
 - `AtomicBucket.request(..)` becomes `MyFixedLimiter.request(..)`
 - `AtomicBucket.raw_request(..)` becomes `MyVarLimiter.request(..)`
 - `AtomicBucket.multi_request(..)` becomes `MyMultiLimiter.request(..)` or
   `MyMultiLimiter.request_details(..)` if the `details: true` option was used

5) Remove all options from macro calls except for `ref`.

6) Remove all AtomicBucket entries from the supervision tree and add each rate 
limiter module. No need to pass parameters manually - its done automatically.
```elixir
# application.ex
children = [MyLimiter1, MyLimiter2, ..]
```

## Caveats

The library makes no effort to ensure that bucket parameters remain
stable across calls: the parameters are not stored at all! Using same bucket
with different parameters will result in silent bugs.

## Benchmarks

The library provides a comprehensive benchmark suite measuring series of rate
limit checks with different parameters and bucket sizes.
See BENCHMARKING.md for more info.

## License

Copyright 2026 Andrey Tretyakov  
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
