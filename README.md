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

 - automatic calculation of bucket parameters based on average rate and burst size

 - handy timeouts for retries

 - support for token refunds and variable cost requests

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
average rate and burst parameters. When possible, call the macro with literal arguments
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

Use `raw_request/5` macro to implement advanced features such as token refunds
or variable cost. It supports same options as `request/5`
```elixir
# This would be 10 req/s with 2 burst requests in fixed cost scenario
{:allow, remaining_tokens, ref} = AtomicBucket.raw_request(:mybucket, 200, 1, 100)
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
mixing `request/5` and `raw_request/5` - it must be avoided.

## Benchmarks

The library provides a benchmark measuring series of 1000 rate limit checks
(see bench/benchmark.exs). It serves as an illustration of available options.
In general, such benchmarks should be taken with a grain of salt:

- they often use artificial conditions different from real life, thus 
  devaluing the results

- above certain point a rate limiter is "fast enough" for many purposes.
  For BEAM this probably means "ETS or faster". Any atomics-based library
  should be much faster than ETS and is likely the fastest you can get.

- comparing results between differently implemented or completely different
  algorithms is neither 100% valid nor very useful. It's very easy to make a
  pointless benchmark measuring wrong things, simply because it's hard to
  make different solutions perform same work achieving same results.

- Tradeoffs are important. It's better to look at the overall picture, rather
  than raw performance.

```shell
$ mix run bench/benchmark.exs
Operating System: Linux
CPU Information: 13th Gen Intel(R) Core(TM) i7-13700K
Number of Available Cores: 24
Available memory: 62.52 GB
Elixir 1.20.0
Erlang 29.0.1
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: none specified
Estimated total run time: 42 s
Excluding outliers: false

Benchmarking raw_request (literals, default opts) ...
Benchmarking raw_request (non-literals, default opts) ...
Benchmarking request (literals, default opts) ...
Benchmarking request (literals, persistent) ...
Benchmarking request (literals, reusing ref) ...
Benchmarking request (non-literals, default opts) ...
Calculating statistics...
Formatting results...

Name                                               ips        average  deviation         median         99th %
request (literals, reusing ref)                11.81 K       84.65 μs    ±13.79%       82.21 μs      135.81 μs
request (literals, persistent)                  8.42 K      118.71 μs    ±11.83%      115.87 μs      193.22 μs
raw_request (literals, default opts)            5.31 K      188.18 μs    ±12.08%      183.14 μs      308.21 μs
request (literals, default opts)                5.29 K      188.90 μs    ±11.78%      184.10 μs      306.53 μs
raw_request (non-literals, default opts)        5.00 K      200.19 μs    ±11.56%      195.08 μs      321.36 μs
request (non-literals, default opts)            4.27 K      234.02 μs    ±10.90%      227.43 μs      353.50 μs

Comparison: 
request (literals, reusing ref)                11.81 K
request (literals, persistent)                  8.42 K - 1.40x slower +34.06 μs
raw_request (literals, default opts)            5.31 K - 2.22x slower +103.53 μs
request (literals, default opts)                5.29 K - 2.23x slower +104.26 μs
raw_request (non-literals, default opts)        5.00 K - 2.37x slower +115.55 μs
request (non-literals, default opts)            4.27 K - 2.76x slower +149.37 μs

Extended statistics: 

Name                                             minimum        maximum    sample size                     mode
request (literals, reusing ref)                 77.47 μs      369.01 μs        58.94 K79.16 μs, 79.58 μs, 79.75
request (literals, persistent)                 110.33 μs      378.21 μs        42.05 K     112.17 μs, 112.11 μs
raw_request (literals, default opts)           164.90 μs      464.82 μs        26.54 K                187.78 μs
request (literals, default opts)               164.81 μs      418.69 μs        26.44 K     186.95 μs, 187.26 μs
raw_request (non-literals, default opts)       176.23 μs      470.45 μs        24.95 K198.13 μs, 189.40 μs, 198
request (non-literals, default opts)           206.55 μs      434.20 μs        21.34 K227.04 μs, 224.74 μs, 227
```

## License

Copyright 2026 Andrey Tretyakov  
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
