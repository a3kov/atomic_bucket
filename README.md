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

 - compile-time validation of arguments when possible

 - may not support all cases and extreme rate limit parameters, see Limitations
   section below

## Installation

Adding it to your list of dependencies in `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:atomic_bucket, "~> 0.1.0"}
  ]
end
```

You must start AtomicBucket server for each bucket table you want to use - without
it the library will not work.

```elixir
children = [.., AtomicBucket, ..]
```
This will once per hour clean buckets that haven't had requests in
the last 24 hours. See `start_link/1` for info about available options.

## Usage

Use `request/5` macro with desired average rate and burst parameters.
When possible, call the macro with literal arguments for better
performance and compile-time validation.

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

# Bucket id can be any term.
``
AtomicBucket.request({:client, ip_addr}, 1, 10, 3)

# Cache bucket reference in :persistent_term for better performance.
# Good fit for buckets with low churn, best for fixed buckets like per-user-id
# rate limits. See :persistent_term docs for more info on the tradeoffs.
AtomicBucket.request(:mybucket, 1, 10, 3, persistent: true)

# Reuse bucket references in long running processes for top performance.
{:allow, _requests, bucket_ref} = AtomicBucket.request(:mybucket, 1, 10, 3)
AtomicBucket.request(:mybucket, 1, 10, 3, ref: bucket_ref)

# To implement different retention policies start multiple servers, and
# use the table option of request/5. Bucket ids are table-scoped and don't
# have to be globally unique.
children = [
  {
    AtomicBucket,
    table: :table1,
    cleanup_interval: :timer.minutes(10),
    max_idle_period: :timer.minutes(10)
  },
  {
    AtomicBucket,
    table: :table1,
    cleanup_interval: :timer.minutes(20),
    max_idle_period: :timer.minutes(30)
  },
]
AtomicBucket.request(:bucket, 1, 10, 3, table: :table1)
AtomicBucket.request(:bucket, 1, 10, 3, table: :table2)
```

## Limitations

The library is optimized for common cases where rate limiters are used.
Extremely slow/fast rates and/or huge bursts may exceed the bucket storage
limits (64 bits). In practice, most people wouldn't need these extreme
parameters.

For now, only fixed cost requests are supported.

## Benchmarks

The library provides a benchmark measuring series of 1000 rate limit checks
(see bench/benchmark.exs). It serves as an illustration of available options,
and doesn't try to compare different libraries. In general, benchmarks
comparing different solutions should be taken with a grain of salt:

- above certain point, a rate limiter is "fast enough" for many purposes.
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
Compiling 1 file (.ex)
Generated atomic_bucket app
Operating System: Linux
CPU Information: 13th Gen Intel(R) Core(TM) i7-13700K
Number of Available Cores: 24
Available memory: 62.61 GB
Elixir 1.19.5
Erlang 27.1.3
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: none specified
Estimated total run time: 36 s
Excluding outliers: false

Benchmarking AtomicBucket (default) ...
Benchmarking AtomicBucket (persistent bucket) ...
Benchmarking AtomicBucket (reusing bucket ref) ...
Calculating statistics...
Formatting results...

Name                                        ips        average  deviation         median         99th %
AtomicBucket (reusing bucket ref)        7.98 K      125.25 μs     ±9.25%      123.19 μs      170.25 μs
AtomicBucket (persistent bucket)         6.02 K      166.02 μs     ±7.60%      164.07 μs      216.57 μs
AtomicBucket (default)                   3.88 K      258.04 μs     ±8.42%      253.24 μs      365.80 μs

Comparison: 
AtomicBucket (reusing bucket ref)        7.98 K
AtomicBucket (persistent bucket)         6.02 K - 1.33x slower +40.77 μs
AtomicBucket (default)                   3.88 K - 2.06x slower +132.79 μs

Extended statistics: 

Name                                      minimum        maximum    sample size                     mode
AtomicBucket (reusing bucket ref)       116.65 μs      497.45 μs        79.72 K                121.52 μs
AtomicBucket (persistent bucket)        155.94 μs     1176.36 μs        60.16 K                162.48 μs
AtomicBucket (default)                  232.99 μs      660.55 μs        38.71 K     249.56 μs, 252.43 μs
```

## License

Copyright 2026 Andrey Tretyakov<br>
The source code of the project is released under Apache License 2.0.
Check LICENSE file for more information.
