# Benchmarking

The included benchmark suite measures series of 1000 rate limit checks. It
serves as an illustration of available options. Run it like so:

```shell
mix run bench/fixed_cost_limiter.exs
mix run bench/variable_cost_limiter.exs
mix run bench/multi_rate_limiter.exs
```

There are 2 bucket sizes in the benchmarks: small and big, depending on the 
required atomic integer. For fixed and variable cost limiters small size means
numbers typical for rate limiters, and big size is called "monster" because it has
extreme parameters, unlikely to be used by anyone. On the other hand,
multi-rate limiter can easily reach big atomic size with 3 or more sub-buckets.

Big buckets take a significant performance hit because of the way big
integers are implemented in BEAM. 32bit architectures take a similar hit with
all types of buckets - for our purposes all integers on 32bit are "big".

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

This benchmark suite, in particular, is heavily biased towards DoS attack 
scenarios, where the vast majority of requests are denied, and doesn't model
realistic concurrent access.

## Example results

The following results were collected on Intel i7-13700K, Elixir 1.20, Erlang 29.
```shell
###############################################################################################################
#                                             FixedCostLimiter                                                #
###############################################################################################################

Benchmarking request (literals, default opts) with input Monster bucket (big atomic) ...
Benchmarking request (literals, default opts) with input Normal bucket (small atomic) ...
Benchmarking request (literals, persistent) with input Monster bucket (big atomic) ...
Benchmarking request (literals, persistent) with input Normal bucket (small atomic) ...
Benchmarking request (literals, reusing ref) with input Monster bucket (big atomic) ...
Benchmarking request (literals, reusing ref) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, default opts) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, default opts) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, persistent) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, persistent) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, reusing ref) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, reusing ref) with input Normal bucket (small atomic) ...
Calculating statistics...
Formatting results...

##### With input Monster bucket (big atomic) #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)             7.43 K      134.57 μs     ±1.59%      134.37 μs      140.49 μs
request (literals, persistent)              6.48 K      154.29 μs     ±2.00%      153.88 μs      162.80 μs
request (non-literals, reusing ref)         5.92 K      168.78 μs     ±2.78%      167.99 μs      180.87 μs
request (non-literals, persistent)          5.35 K      187.08 μs     ±2.80%      185.70 μs      199.89 μs
request (literals, default opts)            4.41 K      226.86 μs     ±3.66%      223.21 μs      248.46 μs
request (non-literals, default opts)        3.84 K      260.57 μs     ±2.84%      260.29 μs      278.10 μs

Comparison: 
request (literals, reusing ref)             7.43 K
request (literals, persistent)              6.48 K - 1.15x slower +19.72 μs
request (non-literals, reusing ref)         5.92 K - 1.25x slower +34.21 μs
request (non-literals, persistent)          5.35 K - 1.39x slower +52.50 μs
request (literals, default opts)            4.41 K - 1.69x slower +92.29 μs
request (non-literals, default opts)        3.84 K - 1.94x slower +126.00 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)            129.02 μs      140.95 μs        32.84 K                133.82 μs
request (literals, persistent)             146.93 μs      163.30 μs        29.71 K                154.23 μs
request (non-literals, reusing ref)        159.86 μs      182.85 μs        28.47 K166.06 μs, 165.93 μs, 165
request (non-literals, persistent)         178.47 μs      203.69 μs        25.80 K184.52 μs, 185.59 μs, 183
request (literals, default opts)           213.02 μs      255.73 μs        20.63 K221.28 μs, 220.77 μs, 221
request (non-literals, default opts)       241.37 μs      281.14 μs        17.85 K259.64 μs, 260.23 μs, 259

##### With input Normal bucket (small atomic) #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)            15.70 K       63.70 μs     ±3.91%       63.55 μs       70.66 μs
request (literals, persistent)             12.38 K       80.78 μs     ±3.44%       80.38 μs       88.52 μs
request (non-literals, reusing ref)        10.36 K       96.54 μs     ±2.23%       96.08 μs      102.42 μs
request (non-literals, persistent)          8.86 K      112.93 μs     ±1.63%      113.13 μs      117.52 μs
request (literals, default opts)            6.76 K      147.99 μs     ±2.04%      147.54 μs      156.53 μs
request (non-literals, default opts)        5.56 K      179.76 μs     ±3.98%      176.19 μs      199.03 μs

Comparison: 
request (literals, reusing ref)            15.70 K
request (literals, persistent)             12.38 K - 1.27x slower +17.08 μs
request (non-literals, reusing ref)        10.36 K - 1.52x slower +32.84 μs
request (non-literals, persistent)          8.86 K - 1.77x slower +49.23 μs
request (literals, default opts)            6.76 K - 2.32x slower +84.29 μs
request (non-literals, default opts)        5.56 K - 2.82x slower +116.06 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)             58.79 μs       71.20 μs        74.54 K                 61.12 μs
request (literals, persistent)              75.99 μs       89.14 μs        59.17 K       81.57 μs, 77.88 μs
request (non-literals, reusing ref)         90.43 μs      102.83 μs        46.98 K                 95.84 μs
request (non-literals, persistent)         107.79 μs      117.81 μs        40.42 K113.10 μs, 113.33 μs, 113
request (literals, default opts)           139.75 μs      156.94 μs        29.53 K     145.57 μs, 145.61 μs
request (non-literals, default opts)       162.74 μs      204.82 μs        25.48 K                174.32 μs

###############################################################################################################
#                                              VariableCostLimiter                                            #
###############################################################################################################

Benchmarking request (literals, default opts) with input Monster bucket (big atomic) ...
Benchmarking request (literals, default opts) with input Normal bucket (small atomic) ...
Benchmarking request (literals, persistent) with input Monster bucket (big atomic) ...
Benchmarking request (literals, persistent) with input Normal bucket (small atomic) ...
Benchmarking request (literals, reusing ref) with input Monster bucket (big atomic) ...
Benchmarking request (literals, reusing ref) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, default opts) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, default opts) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, persistent) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, persistent) with input Normal bucket (small atomic) ...
Benchmarking request (non-literals, reusing ref) with input Monster bucket (big atomic) ...
Benchmarking request (non-literals, reusing ref) with input Normal bucket (small atomic) ...
Calculating statistics...
Formatting results...

##### With input Monster bucket (big atomic) #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)             7.60 K      131.58 μs     ±1.68%      131.17 μs      137.84 μs
request (non-literals, reusing ref)         7.41 K      134.91 μs     ±1.99%      134.09 μs      143.05 μs
request (literals, persistent)              6.66 K      150.26 μs     ±1.64%      149.71 μs      157.08 μs
request (non-literals, persistent)          6.43 K      155.64 μs     ±2.01%      155.12 μs      164.09 μs
request (literals, default opts)            4.42 K      226.43 μs     ±3.40%      222.97 μs      246.59 μs
request (non-literals, default opts)        4.28 K      233.41 μs     ±3.60%      233.71 μs      251.38 μs

Comparison: 
request (literals, reusing ref)             7.60 K
request (non-literals, reusing ref)         7.41 K - 1.03x slower +3.34 μs
request (literals, persistent)              6.66 K - 1.14x slower +18.68 μs
request (non-literals, persistent)          6.43 K - 1.18x slower +24.06 μs
request (literals, default opts)            4.42 K - 1.72x slower +94.86 μs
request (non-literals, default opts)        4.28 K - 1.77x slower +101.83 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)            126.16 μs      138.34 μs        33.42 K                130.91 μs
request (non-literals, reusing ref)        129.05 μs      143.78 μs        32.82 K                133.43 μs
request (literals, persistent)             143.63 μs      157.45 μs        29.77 K                149.23 μs
request (non-literals, persistent)         146.97 μs      164.77 μs        29.54 K                155.08 μs
request (literals, default opts)           210.23 μs      253.04 μs        20.72 K                221.38 μs
request (non-literals, default opts)       212.58 μs      256.41 μs        19.95 K     227.13 μs, 233.43 μs

##### With input Normal bucket (small atomic) #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)            16.79 K       59.55 μs     ±3.96%       59.50 μs       65.89 μs
request (non-literals, reusing ref)        16.50 K       60.61 μs     ±3.73%       60.50 μs       66.78 μs
request (literals, persistent)             13.26 K       75.40 μs     ±3.07%       75.54 μs       82.00 μs
request (non-literals, persistent)         12.97 K       77.08 μs     ±2.92%       77.16 μs       83.54 μs
request (literals, default opts)            6.84 K      146.27 μs     ±1.97%      145.88 μs      154.08 μs
request (non-literals, default opts)        6.78 K      147.47 μs     ±1.81%      147.31 μs      154.97 μs

Comparison: 
request (literals, reusing ref)            16.79 K
request (non-literals, reusing ref)        16.50 K - 1.02x slower +1.05 μs
request (literals, persistent)             13.26 K - 1.27x slower +15.85 μs
request (non-literals, persistent)         12.97 K - 1.29x slower +17.52 μs
request (literals, default opts)            6.84 K - 2.46x slower +86.72 μs
request (non-literals, default opts)        6.78 K - 2.48x slower +87.92 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)             55.36 μs       66.81 μs        79.61 K                 57.11 μs
request (non-literals, reusing ref)         56.24 μs       67.50 μs        77.13 K                 58.13 μs
request (literals, persistent)              71.03 μs       82.57 μs        60.14 K                 72.82 μs
request (non-literals, persistent)          72.53 μs       84.09 μs        59.69 K                 77.87 μs
request (literals, default opts)           138.90 μs      154.53 μs        29.80 K                146.07 μs
request (non-literals, default opts)       140.22 μs      155.36 μs        29.10 K     147.72 μs, 146.90 μs

###############################################################################################################
#                                                 MultiRateLimiter                                            #
###############################################################################################################

Benchmarking request (literals, default opts) with input 2 buckets ...
Benchmarking request (literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking request (literals, default opts) with input 3 buckets (small atomic) ...
Benchmarking request (literals, persistent) with input 2 buckets ...
Benchmarking request (literals, persistent) with input 3 buckets (big atomic) ...
Benchmarking request (literals, persistent) with input 3 buckets (small atomic) ...
Benchmarking request (literals, reusing ref) with input 2 buckets ...
Benchmarking request (literals, reusing ref) with input 3 buckets (big atomic) ...
Benchmarking request (literals, reusing ref) with input 3 buckets (small atomic) ...
Benchmarking request (non-literals, default opts) with input 2 buckets ...
Benchmarking request (non-literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking request (non-literals, default opts) with input 3 buckets (small atomic) ...
Benchmarking request (non-literals, persistent) with input 2 buckets ...
Benchmarking request (non-literals, persistent) with input 3 buckets (big atomic) ...
Benchmarking request (non-literals, persistent) with input 3 buckets (small atomic) ...
Benchmarking request (non-literals, reusing ref) with input 2 buckets ...
Benchmarking request (non-literals, reusing ref) with input 3 buckets (big atomic) ...
Benchmarking request (non-literals, reusing ref) with input 3 buckets (small atomic) ...
Benchmarking request_details (literals, default opts) with input 2 buckets ...
Benchmarking request_details (literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking request_details (literals, default opts) with input 3 buckets (small atomic) ...
Benchmarking request_details (non-literals, default opts) with input 2 buckets ...
Benchmarking request_details (non-literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking request_details (non-literals, default opts) with input 3 buckets (small atomic) ...
Calculating statistics...
Formatting results...

##### With input 2 buckets #####
Name                                                   ips        average  deviation         median         99th %
request (literals, reusing ref)                    10.12 K       98.85 μs     ±3.38%       99.26 μs      105.82 μs
request (literals, persistent)                      8.43 K      118.60 μs     ±2.29%      118.56 μs      125.01 μs
request (literals, default opts)                    5.26 K      190.05 μs     ±3.38%      190.39 μs      205.11 μs
request_details (literals, default opts)            4.64 K      215.49 μs     ±1.50%      216.01 μs      223.47 μs
request (non-literals, reusing ref)                 3.76 K      265.74 μs     ±1.93%      265.55 μs      278.73 μs
request (non-literals, persistent)                  3.63 K      275.42 μs     ±1.59%      275.58 μs      286.49 μs
request (non-literals, default opts)                2.77 K      360.77 μs     ±1.90%      360.82 μs      381.73 μs
request_details (non-literals, default opts)        2.27 K      440.32 μs    ±12.75%      411.39 μs      589.47 μs

Comparison: 
request (literals, reusing ref)                    10.12 K
request (literals, persistent)                      8.43 K - 1.20x slower +19.75 μs
request (literals, default opts)                    5.26 K - 1.92x slower +91.20 μs
request_details (literals, default opts)            4.64 K - 2.18x slower +116.65 μs
request (non-literals, reusing ref)                 3.76 K - 2.69x slower +166.89 μs
request (non-literals, persistent)                  3.63 K - 2.79x slower +176.57 μs
request (non-literals, default opts)                2.77 K - 3.65x slower +261.92 μs
request_details (non-literals, default opts)        2.27 K - 4.45x slower +341.48 μs

Extended statistics: 

Name                                                 minimum        maximum    sample size                     mode
request (literals, reusing ref)                     89.75 μs      108.27 μs        48.05 K                 99.50 μs
request (literals, persistent)                     110.71 μs      126.46 μs        38.57 K                119.43 μs
request (literals, default opts)                   171.96 μs      210.20 μs        23.35 K196.72 μs, 190.69 μs, 194
request_details (literals, default opts)           205.27 μs      225.97 μs        21.71 K216.83 μs, 216.88 μs, 217
request (non-literals, reusing ref)                252.32 μs      280.46 μs        16.96 K                263.68 μs
request (non-literals, persistent)                 263.45 μs      288.46 μs        16.39 K274.80 μs, 275.85 μs, 275
request (non-literals, default opts)               340.10 μs      386.48 μs        11.11 K     360.76 μs, 363.02 μs
request_details (non-literals, default opts)       381.58 μs      610.80 μs        11.07 K403.37 μs, 399.61 μs, 406

##### With input 3 buckets (big atomic) #####
Name                                                   ips        average  deviation         median         99th %
request (literals, reusing ref)                     6.93 K      144.24 μs     ±2.94%      143.21 μs      155.30 μs
request (literals, persistent)                      6.16 K      162.26 μs     ±2.39%      161.47 μs      172.84 μs
request (literals, default opts)                    4.12 K      242.77 μs     ±2.67%      241.17 μs      260.13 μs
request_details (literals, default opts)            2.97 K      336.42 μs    ±14.59%      331.44 μs      468.79 μs
request (non-literals, reusing ref)                 2.57 K      389.30 μs     ±3.26%      387.64 μs      419.76 μs
request (non-literals, persistent)                  2.50 K      399.40 μs     ±2.96%      397.17 μs      428.72 μs
request (non-literals, default opts)                2.04 K      491.25 μs     ±3.24%      491.49 μs      538.47 μs
request_details (non-literals, default opts)        1.77 K      566.13 μs     ±4.41%      561.83 μs      648.71 μs

Comparison: 
request (literals, reusing ref)                     6.93 K
request (literals, persistent)                      6.16 K - 1.12x slower +18.02 μs
request (literals, default opts)                    4.12 K - 1.68x slower +98.53 μs
request_details (literals, default opts)            2.97 K - 2.33x slower +192.18 μs
request (non-literals, reusing ref)                 2.57 K - 2.70x slower +245.06 μs
request (non-literals, persistent)                  2.50 K - 2.77x slower +255.15 μs
request (non-literals, default opts)                2.04 K - 3.41x slower +347.01 μs
request_details (non-literals, default opts)        1.77 K - 3.92x slower +421.89 μs

Extended statistics: 

Name                                                 minimum        maximum    sample size                     mode
request (literals, reusing ref)                    133.83 μs      155.79 μs        32.28 K                142.36 μs
request (literals, persistent)                     151.98 μs      173.25 μs        27.30 K                162.17 μs
request (literals, default opts)                   223.57 μs      264.56 μs        18.65 K239.58 μs, 238.95 μs, 239
request_details (literals, default opts)           246.34 μs      501.37 μs        14.56 K307.77 μs, 254.39 μs, 298
request (non-literals, reusing ref)                363.36 μs      432.17 μs        12.25 K382.16 μs, 402.33 μs, 382
request (non-literals, persistent)                 371.10 μs      438.09 μs        11.93 K394.02 μs, 384.18 μs, 408
request (non-literals, default opts)               453.25 μs      540.81 μs         8.52 K478.05 μs, 497.70 μs, 498
request_details (non-literals, default opts)       518.86 μs      658.48 μs         7.15 K555.09 μs, 551.13 μs, 560

##### With input 3 buckets (small atomic) #####
Name                                                   ips        average  deviation         median         99th %
request (literals, reusing ref)                     9.79 K      102.15 μs     ±3.82%      102.51 μs      110.68 μs
request (literals, persistent)                      8.15 K      122.68 μs     ±2.54%      122.47 μs      130.45 μs
request (literals, default opts)                    5.11 K      195.51 μs     ±2.67%      195.53 μs      208.40 μs
request_details (literals, default opts)            3.63 K      275.41 μs    ±10.17%      267.38 μs      350.96 μs
request (non-literals, reusing ref)                 3.14 K      318.64 μs     ±2.24%      317.55 μs      338.88 μs
request (non-literals, persistent)                  3.04 K      329.19 μs     ±1.90%      328.66 μs      346.03 μs
request (non-literals, default opts)                2.40 K      416.73 μs     ±2.14%      415.52 μs      449.12 μs
request_details (non-literals, default opts)        2.01 K      497.21 μs     ±5.33%      489.73 μs      588.58 μs

Comparison: 
request (literals, reusing ref)                     9.79 K
request (literals, persistent)                      8.15 K - 1.20x slower +20.54 μs
request (literals, default opts)                    5.11 K - 1.91x slower +93.36 μs
request_details (literals, default opts)            3.63 K - 2.70x slower +173.27 μs
request (non-literals, reusing ref)                 3.14 K - 3.12x slower +216.49 μs
request (non-literals, persistent)                  3.04 K - 3.22x slower +227.05 μs
request (non-literals, default opts)                2.40 K - 4.08x slower +314.58 μs
request_details (non-literals, default opts)        2.01 K - 4.87x slower +395.07 μs

Extended statistics: 

Name                                                 minimum        maximum    sample size                     mode
request (literals, reusing ref)                     91.65 μs      113.71 μs        46.80 K                104.28 μs
request (literals, persistent)                     114.97 μs      131.81 μs        38.64 K123.02 μs, 120.91 μs, 121
request (literals, default opts)                   179.28 μs      213.07 μs        22.17 K191.80 μs, 197.38 μs, 190
request_details (literals, default opts)           196.55 μs      361.00 μs        15.82 K274.50 μs, 261.44 μs, 269
request (non-literals, reusing ref)                303.65 μs      341.47 μs        14.29 K                314.00 μs
request (non-literals, persistent)                 316.37 μs      348.37 μs        13.88 K                324.93 μs
request (non-literals, default opts)               395.73 μs      452.55 μs         9.55 K419.71 μs, 420.12 μs, 406
request_details (non-literals, default opts)       455.85 μs      594.72 μs         8.17 K                487.65 μs
```