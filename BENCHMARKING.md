# Benchmarking

The included benchmark suite measures series of 1000 rate limit checks. It
serves as an illustration of available options. Run it like so:

```shell
mix run bench/request.exs
mix run bench/raw_request.exs
mix run bench/multi_request.exs
```

There are 2 bucket sizes in the benchmarks: small and big, depending on the 
required atomic integer. For request and raw_request small size means numbers
typical for rate limiters, and big size is called "monster" because it has
extreme parameters, unlikely to be used by anyone. On the other hand,
multi_request can easily reach big atomic size with 3 or more sub-buckets.

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
#                                                R E Q U E S T                                                #
###############################################################################################################

Benchmarking request (literals, default opts) with input Monster bucket (extreme size) ...
Benchmarking request (literals, default opts) with input Normal bucket ...
Benchmarking request (literals, persistent) with input Monster bucket (extreme size) ...
Benchmarking request (literals, persistent) with input Normal bucket ...
Benchmarking request (literals, reusing ref) with input Monster bucket (extreme size) ...
Benchmarking request (literals, reusing ref) with input Normal bucket ...
Benchmarking request (non-literals, default opts) with input Monster bucket (extreme size) ...
Benchmarking request (non-literals, default opts) with input Normal bucket ...
Benchmarking request (non-literals, persistent) with input Monster bucket (extreme size) ...
Benchmarking request (non-literals, persistent) with input Normal bucket ...
Benchmarking request (non-literals, reusing ref) with input Monster bucket (extreme size) ...
Benchmarking request (non-literals, reusing ref) with input Normal bucket ...
Calculating statistics...
Formatting results...

##### With input Monster bucket (extreme size) #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)             7.60 K      131.57 μs     ±1.51%      131.50 μs      137.24 μs
request (non-literals, reusing ref)         6.20 K      161.25 μs     ±3.20%      159.35 μs      174.77 μs
request (literals, persistent)              6.01 K      166.46 μs     ±1.85%      166.16 μs      175.48 μs
request (non-literals, persistent)          5.12 K      195.48 μs     ±2.94%      194.15 μs      209.66 μs
request (literals, default opts)            4.30 K      232.56 μs     ±3.51%      232.38 μs      250.76 μs
request (non-literals, default opts)        3.77 K      265.55 μs     ±3.06%      265.10 μs      284.86 μs

Comparison: 
request (literals, reusing ref)             7.60 K
request (non-literals, reusing ref)         6.20 K - 1.23x slower +29.68 μs
request (literals, persistent)              6.01 K - 1.27x slower +34.89 μs
request (non-literals, persistent)          5.12 K - 1.49x slower +63.91 μs
request (literals, default opts)            4.30 K - 1.77x slower +100.99 μs
request (non-literals, default opts)        3.77 K - 2.02x slower +133.98 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)            126.05 μs      137.61 μs        33.90 K     131.75 μs, 131.63 μs
request (non-literals, reusing ref)        153.88 μs      179.15 μs        29.79 K                156.03 μs
request (literals, persistent)             161.73 μs      176.07 μs        27.21 K     166.59 μs, 163.07 μs
request (non-literals, persistent)         185.71 μs      214.84 μs        24.75 K     190.63 μs, 190.27 μs
request (literals, default opts)           214.40 μs      254.45 μs        20.05 K     230.26 μs, 230.14 μs
request (non-literals, default opts)       244.23 μs      289.68 μs        17.57 K                263.16 μs

##### With input Normal bucket #####
Name                                           ips        average  deviation         median         99th %
request (literals, reusing ref)            16.03 K       62.39 μs     ±3.75%       62.33 μs       68.80 μs
request (literals, persistent)             10.95 K       91.35 μs     ±2.89%       91.08 μs       98.65 μs
request (non-literals, reusing ref)        10.47 K       95.56 μs     ±2.16%       95.19 μs      101.39 μs
request (non-literals, persistent)          8.02 K      124.72 μs     ±1.71%      124.20 μs      130.28 μs
request (literals, default opts)            6.29 K      158.90 μs     ±2.25%      157.65 μs      169.13 μs
request (non-literals, default opts)        5.21 K      192.00 μs     ±3.80%      190.88 μs      211.21 μs

Comparison: 
request (literals, reusing ref)            16.03 K
request (literals, persistent)             10.95 K - 1.46x slower +28.96 μs
request (non-literals, reusing ref)        10.47 K - 1.53x slower +33.16 μs
request (non-literals, persistent)          8.02 K - 2.00x slower +62.33 μs
request (literals, default opts)            6.29 K - 2.55x slower +96.51 μs
request (non-literals, default opts)        5.21 K - 3.08x slower +129.60 μs

Extended statistics: 

Name                                         minimum        maximum    sample size                     mode
request (literals, reusing ref)             58.10 μs       69.49 μs        75.02 K                 62.65 μs
request (literals, persistent)              86.70 μs       99.11 μs        50.52 K                 88.43 μs
request (non-literals, reusing ref)         89.91 μs      101.82 μs        48.21 K                 93.77 μs
request (non-literals, persistent)         119.33 μs      130.64 μs        36.70 K                123.74 μs
request (literals, default opts)           148.41 μs      169.79 μs        28.13 K156.22 μs, 155.94 μs, 156
request (non-literals, default opts)       174.46 μs      217.00 μs        23.82 K183.58 μs, 183.48 μs, 186

###############################################################################################################
#                                              R A W  R E Q U E S T                                           #
###############################################################################################################

Benchmarking raw_request (literals, default opts) with input Monster bucket (extreme size) ...
Benchmarking raw_request (literals, default opts) with input Normal bucket ...
Benchmarking raw_request (literals, persistent) with input Monster bucket (extreme size) ...
Benchmarking raw_request (literals, persistent) with input Normal bucket ...
Benchmarking raw_request (literals, reusing ref) with input Monster bucket (extreme size) ...
Benchmarking raw_request (literals, reusing ref) with input Normal bucket ...
Benchmarking raw_request (non-literals, default opts) with input Monster bucket (extreme size) ...
Benchmarking raw_request (non-literals, default opts) with input Normal bucket ...
Benchmarking raw_request (non-literals, persistent) with input Monster bucket (extreme size) ...
Benchmarking raw_request (non-literals, persistent) with input Normal bucket ...
Benchmarking raw_request (non-literals, reusing ref) with input Monster bucket (extreme size) ...
Benchmarking raw_request (non-literals, reusing ref) with input Normal bucket ...
Calculating statistics...
Formatting results...

##### With input Monster bucket (extreme size) #####
Name                                               ips        average  deviation         median         99th %
raw_request (literals, reusing ref)             7.63 K      131.07 μs     ±1.47%      130.93 μs      136.58 μs
raw_request (non-literals, reusing ref)         7.33 K      136.49 μs     ±1.41%      136.38 μs      141.90 μs
raw_request (literals, persistent)              6.15 K      162.65 μs     ±1.79%      162.23 μs      170.44 μs
raw_request (non-literals, persistent)          5.85 K      171.05 μs     ±1.69%      170.26 μs      178.70 μs
raw_request (literals, default opts)            4.29 K      233.35 μs     ±3.54%      233.71 μs      251.26 μs
raw_request (non-literals, default opts)        4.16 K      240.67 μs     ±3.48%      240.62 μs      259.63 μs

Comparison: 
raw_request (literals, reusing ref)             7.63 K
raw_request (non-literals, reusing ref)         7.33 K - 1.04x slower +5.42 μs
raw_request (literals, persistent)              6.15 K - 1.24x slower +31.58 μs
raw_request (non-literals, persistent)          5.85 K - 1.31x slower +39.98 μs
raw_request (literals, default opts)            4.29 K - 1.78x slower +102.28 μs
raw_request (non-literals, default opts)        4.16 K - 1.84x slower +109.60 μs

Extended statistics: 

Name                                             minimum        maximum    sample size                     mode
raw_request (literals, reusing ref)            126.39 μs      136.93 μs        33.30 K                130.77 μs
raw_request (non-literals, reusing ref)        131.66 μs      142.30 μs        31.84 K     136.66 μs, 136.30 μs
raw_request (literals, persistent)             157.35 μs      170.85 μs        27.97 K                162.05 μs
raw_request (non-literals, persistent)         164.75 μs      179.18 μs        26.76 K                169.68 μs
raw_request (literals, default opts)           214.47 μs      256.00 μs        20.04 K229.32 μs, 229.12 μs, 229
raw_request (non-literals, default opts)       222.01 μs      263.78 μs        19.36 K                237.91 μs

##### With input Normal bucket #####
Name                                               ips        average  deviation         median         99th %
raw_request (literals, reusing ref)            15.99 K       62.52 μs     ±4.26%       62.41 μs       69.90 μs
raw_request (non-literals, reusing ref)        15.99 K       62.53 μs     ±4.16%       62.47 μs       69.77 μs
raw_request (non-literals, persistent)         10.86 K       92.08 μs     ±3.00%       91.69 μs       99.85 μs
raw_request (literals, persistent)             10.52 K       95.06 μs     ±3.14%       94.82 μs      102.86 μs
raw_request (literals, default opts)            6.30 K      158.81 μs     ±2.37%      158.07 μs      169.50 μs
raw_request (non-literals, default opts)        6.26 K      159.62 μs     ±2.03%      158.79 μs      168.84 μs

Comparison: 
raw_request (literals, reusing ref)            15.99 K
raw_request (non-literals, reusing ref)        15.99 K - 1.00x slower +0.00544 μs
raw_request (non-literals, persistent)         10.86 K - 1.47x slower +29.56 μs
raw_request (literals, persistent)             10.52 K - 1.52x slower +32.53 μs
raw_request (literals, default opts)            6.30 K - 2.54x slower +96.29 μs
raw_request (non-literals, default opts)        6.26 K - 2.55x slower +97.10 μs

Extended statistics: 

Name                                             minimum        maximum    sample size                     mode
raw_request (literals, reusing ref)             58.10 μs       70.55 μs        75.63 K                 60.08 μs
raw_request (non-literals, reusing ref)         58.33 μs       70.48 μs        75.45 K                 59.02 μs
raw_request (non-literals, persistent)          87.45 μs      100.20 μs        50.43 K                 91.20 μs
raw_request (literals, persistent)              90.22 μs      103.40 μs        49.57 K                 93.73 μs
raw_request (literals, default opts)           147.20 μs      170.35 μs        28.54 K     155.46 μs, 155.41 μs
raw_request (non-literals, default opts)       149.91 μs      169.48 μs        28.19 K                156.78 μs

###############################################################################################################
#                                            M U L T I  R E Q U E S T                                         #
###############################################################################################################

Benchmarking multi_request (literals, default opts) with input 2 buckets ...
Benchmarking multi_request (literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking multi_request (literals, default opts) with input 3 buckets (small atomic) ...
Benchmarking multi_request (literals, details) with input 2 buckets ...
Benchmarking multi_request (literals, details) with input 3 buckets (big atomic) ...
Benchmarking multi_request (literals, details) with input 3 buckets (small atomic) ...
Benchmarking multi_request (literals, persistent) with input 2 buckets ...
Benchmarking multi_request (literals, persistent) with input 3 buckets (big atomic) ...
Benchmarking multi_request (literals, persistent) with input 3 buckets (small atomic) ...
Benchmarking multi_request (literals, reusing ref) with input 2 buckets ...
Benchmarking multi_request (literals, reusing ref) with input 3 buckets (big atomic) ...
Benchmarking multi_request (literals, reusing ref) with input 3 buckets (small atomic) ...
Benchmarking multi_request (non-literals, default opts) with input 2 buckets ...
Benchmarking multi_request (non-literals, default opts) with input 3 buckets (big atomic) ...
Benchmarking multi_request (non-literals, default opts) with input 3 buckets (small atomic) ...
Benchmarking multi_request (non-literals, details) with input 2 buckets ...
Benchmarking multi_request (non-literals, details) with input 3 buckets (big atomic) ...
Benchmarking multi_request (non-literals, details) with input 3 buckets (small atomic) ...
Benchmarking multi_request (non-literals, persistent) with input 2 buckets ...
Benchmarking multi_request (non-literals, persistent) with input 3 buckets (big atomic) ...
Benchmarking multi_request (non-literals, persistent) with input 3 buckets (small atomic) ...
Benchmarking multi_request (non-literals, reusing ref) with input 2 buckets ...
Benchmarking multi_request (non-literals, reusing ref) with input 3 buckets (big atomic) ...
Benchmarking multi_request (non-literals, reusing ref) with input 3 buckets (small atomic) ...
Calculating statistics...
Formatting results...

##### With input 2 buckets #####
Name                                                 ips        average  deviation         median         99th %
multi_request (literals, reusing ref)            10.59 K       94.41 μs     ±3.37%       94.22 μs      102.52 μs
multi_request (literals, persistent)              7.70 K      129.93 μs     ±2.44%      129.97 μs      138.19 μs
multi_request (literals, default opts)            5.00 K      199.92 μs     ±2.81%      200.02 μs      212.61 μs
multi_request (literals, details)                 4.39 K      227.86 μs     ±1.02%      227.99 μs      233.72 μs
multi_request (non-literals, reusing ref)         3.62 K      276.04 μs     ±1.88%      275.77 μs      289.40 μs
multi_request (non-literals, persistent)          3.21 K      311.85 μs     ±1.37%      311.70 μs      322.83 μs
multi_request (non-literals, default opts)        2.61 K      383.75 μs     ±1.69%      383.37 μs      401.98 μs
multi_request (non-literals, details)             2.16 K      463.15 μs    ±12.58%      432.98 μs      623.01 μs

Comparison: 
multi_request (literals, reusing ref)            10.59 K
multi_request (literals, persistent)              7.70 K - 1.38x slower +35.52 μs
multi_request (literals, default opts)            5.00 K - 2.12x slower +105.50 μs
multi_request (literals, details)                 4.39 K - 2.41x slower +133.45 μs
multi_request (non-literals, reusing ref)         3.62 K - 2.92x slower +181.63 μs
multi_request (non-literals, persistent)          3.21 K - 3.30x slower +217.43 μs
multi_request (non-literals, default opts)        2.61 K - 4.06x slower +289.33 μs
multi_request (non-literals, details)             2.16 K - 4.91x slower +368.73 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)             85.51 μs      103.66 μs        49.42 K93.89 μs, 93.71 μs, 94.88
multi_request (literals, persistent)             121.28 μs      139.38 μs        34.11 K130.75 μs, 130.96 μs, 130
multi_request (literals, default opts)           183.33 μs      217.99 μs        22.13 K195.96 μs, 203.10 μs, 198
multi_request (literals, details)                221.81 μs      234.55 μs        20.07 K                227.76 μs
multi_request (non-literals, reusing ref)        261.70 μs      291.54 μs        15.64 K                275.44 μs
multi_request (non-literals, persistent)         299.92 μs      324.39 μs        13.94 K311.44 μs, 311.65 μs, 309
multi_request (non-literals, default opts)       364.67 μs      408.70 μs        10.42 K                381.26 μs
multi_request (non-literals, details)            399.69 μs      642.81 μs        10.54 K424.80 μs, 424.74 μs, 426

##### With input 3 buckets (big atomic) #####
Name                                                 ips        average  deviation         median         99th %
multi_request (literals, reusing ref)             6.83 K      146.48 μs     ±3.47%      144.96 μs      159.65 μs
multi_request (literals, persistent)              5.31 K      188.15 μs     ±3.76%      185.71 μs      209.07 μs
multi_request (literals, default opts)            3.88 K      257.80 μs     ±3.34%      254.90 μs      284.34 μs
multi_request (literals, details)                 2.75 K      363.03 μs    ±13.02%      348.53 μs      498.97 μs
multi_request (non-literals, reusing ref)         2.48 K      403.98 μs     ±3.58%      403.43 μs      444.53 μs
multi_request (non-literals, persistent)          2.30 K      433.95 μs     ±3.32%      432.30 μs      470.48 μs
multi_request (non-literals, default opts)        1.91 K      523.40 μs     ±4.43%      518.39 μs      587.30 μs
multi_request (non-literals, details)             1.69 K      590.65 μs     ±5.01%      582.97 μs      693.45 μs

Comparison: 
multi_request (literals, reusing ref)             6.83 K
multi_request (literals, persistent)              5.31 K - 1.28x slower +41.67 μs
multi_request (literals, default opts)            3.88 K - 1.76x slower +111.33 μs
multi_request (literals, details)                 2.75 K - 2.48x slower +216.55 μs
multi_request (non-literals, reusing ref)         2.48 K - 2.76x slower +257.50 μs
multi_request (non-literals, persistent)          2.30 K - 2.96x slower +287.47 μs
multi_request (non-literals, default opts)        1.91 K - 3.57x slower +376.92 μs
multi_request (non-literals, details)             1.69 K - 4.03x slower +444.17 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)            136.49 μs      160.77 μs        32.04 K                143.69 μs
multi_request (literals, persistent)             176.24 μs      212.95 μs        24.08 K                182.63 μs
multi_request (literals, default opts)           236.85 μs      287.57 μs        17.23 K     250.66 μs, 251.11 μs
multi_request (literals, details)                272.87 μs      521.00 μs        13.13 K     333.76 μs, 346.67 μs
multi_request (non-literals, reusing ref)        376.33 μs      451.74 μs        11.41 K387.13 μs, 395.10 μs, 418
multi_request (non-literals, persistent)         405.11 μs      480.27 μs        10.89 K                438.41 μs
multi_request (non-literals, default opts)       479.59 μs      595.38 μs         8.51 K                501.06 μs
multi_request (non-literals, details)            542.01 μs      701.74 μs         6.83 K                577.98 μs

##### With input 3 buckets (small atomic) #####
Name                                                 ips        average  deviation         median         99th %
multi_request (literals, reusing ref)            10.07 K       99.35 μs     ±3.44%       99.34 μs      107.84 μs
multi_request (literals, persistent)              7.70 K      129.80 μs     ±2.60%      129.31 μs      138.86 μs
multi_request (literals, default opts)            4.82 K      207.43 μs     ±2.61%      207.56 μs      220.89 μs
multi_request (literals, details)                 3.37 K      296.70 μs    ±11.74%      285.46 μs      400.36 μs
multi_request (non-literals, reusing ref)         3.04 K      328.96 μs     ±1.91%      328.56 μs      345.51 μs
multi_request (non-literals, persistent)          2.76 K      362.94 μs     ±1.83%      362.09 μs      380.98 μs
multi_request (non-literals, default opts)        2.28 K      438.45 μs     ±1.50%      438.19 μs      458.90 μs
multi_request (non-literals, details)             1.93 K      517.09 μs     ±5.11%      510.02 μs      607.47 μs

Comparison: 
multi_request (literals, reusing ref)            10.07 K
multi_request (literals, persistent)              7.70 K - 1.31x slower +30.45 μs
multi_request (literals, default opts)            4.82 K - 2.09x slower +108.09 μs
multi_request (literals, details)                 3.37 K - 2.99x slower +197.35 μs
multi_request (non-literals, reusing ref)         3.04 K - 3.31x slower +229.62 μs
multi_request (non-literals, persistent)          2.76 K - 3.65x slower +263.59 μs
multi_request (non-literals, default opts)        2.28 K - 4.41x slower +339.10 μs
multi_request (non-literals, details)             1.93 K - 5.20x slower +417.74 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)             90.95 μs      108.98 μs        47.35 K                 99.54 μs
multi_request (literals, persistent)             122.00 μs      139.88 μs        35.51 K                128.95 μs
multi_request (literals, default opts)           190.40 μs      225.81 μs        20.82 K210.11 μs, 210.26 μs, 207
multi_request (literals, details)                206.01 μs      408.84 μs        15.07 K265.91 μs, 281.95 μs, 269
multi_request (non-literals, reusing ref)        311.63 μs      347.80 μs        13.74 K     330.48 μs, 327.74 μs
multi_request (non-literals, persistent)         346.90 μs      383.00 μs        12.53 K364.73 μs, 358.43 μs, 362
multi_request (non-literals, default opts)       417.93 μs      467.11 μs         8.89 K433.35 μs, 438.35 μs, 439
multi_request (non-literals, details)            475.56 μs      617.75 μs         7.78 K506.33 μs, 496.89 μs, 508
```