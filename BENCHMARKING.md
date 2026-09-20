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
multi_request (literals, reusing ref)            10.57 K       94.60 μs     ±3.20%       94.41 μs      102.09 μs
multi_request (literals, persistent)              7.90 K      126.63 μs     ±2.30%      126.62 μs      133.73 μs
multi_request (literals, default opts)            5.05 K      197.86 μs     ±2.97%      197.82 μs      211.28 μs
multi_request (literals, details)                 4.41 K      226.96 μs     ±1.00%      226.99 μs      232.28 μs
multi_request (non-literals, reusing ref)         3.88 K      257.64 μs     ±2.28%      257.02 μs      272.57 μs
multi_request (non-literals, persistent)          3.44 K      290.78 μs     ±1.72%      290.89 μs      303.41 μs
multi_request (non-literals, default opts)        2.72 K      367.70 μs     ±1.64%      367.36 μs      385.40 μs
multi_request (non-literals, details)             2.16 K      463.65 μs    ±12.72%      431.07 μs      624.16 μs

Comparison: 
multi_request (literals, reusing ref)            10.57 K
multi_request (literals, persistent)              7.90 K - 1.34x slower +32.03 μs
multi_request (literals, default opts)            5.05 K - 2.09x slower +103.26 μs
multi_request (literals, details)                 4.41 K - 2.40x slower +132.36 μs
multi_request (non-literals, reusing ref)         3.88 K - 2.72x slower +163.04 μs
multi_request (non-literals, persistent)          3.44 K - 3.07x slower +196.17 μs
multi_request (non-literals, default opts)        2.72 K - 3.89x slower +273.10 μs
multi_request (non-literals, details)             2.16 K - 4.90x slower +369.05 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)             86.04 μs      103.23 μs        50.61 K       94.29 μs, 93.53 μs
multi_request (literals, persistent)             118.49 μs      135.01 μs        37.22 K     127.07 μs, 126.98 μs
multi_request (literals, default opts)           180.45 μs      216.94 μs        22.44 K203.12 μs, 196.44 μs, 195
multi_request (literals, details)                220.47 μs      233.64 μs        20.99 K226.53 μs, 227.50 μs, 227
multi_request (non-literals, reusing ref)        242.15 μs      274.95 μs        17.66 K255.56 μs, 260.07 μs, 254
multi_request (non-literals, persistent)         277.63 μs      304.99 μs        15.38 K                290.58 μs
multi_request (non-literals, default opts)       350.17 μs      390.32 μs        10.88 K368.66 μs, 364.62 μs, 367
multi_request (non-literals, details)            405.90 μs      641.70 μs        10.48 K419.10 μs, 421.76 μs, 422

##### With input 3 buckets (big atomic) #####
Name                                                 ips        average  deviation         median         99th %
multi_request (literals, reusing ref)             7.06 K      141.73 μs     ±2.45%      141.08 μs      151.63 μs
multi_request (literals, persistent)              5.64 K      177.29 μs     ±2.69%      175.89 μs      189.18 μs
multi_request (literals, default opts)            3.93 K      254.35 μs     ±2.79%      252.05 μs      274.03 μs
multi_request (literals, details)                 2.77 K      361.09 μs    ±12.18%      350.08 μs      487.12 μs
multi_request (non-literals, reusing ref)         2.58 K      387.07 μs     ±3.79%      384.30 μs      426.67 μs
multi_request (non-literals, persistent)          2.34 K      426.51 μs     ±3.06%      423.01 μs      459.52 μs
multi_request (non-literals, default opts)        2.00 K      499.52 μs     ±3.17%      501.19 μs      550.20 μs
multi_request (non-literals, details)             1.70 K      588.12 μs     ±4.38%      582.24 μs      676.03 μs

Comparison: 
multi_request (literals, reusing ref)             7.06 K
multi_request (literals, persistent)              5.64 K - 1.25x slower +35.56 μs
multi_request (literals, default opts)            3.93 K - 1.79x slower +112.62 μs
multi_request (literals, details)                 2.77 K - 2.55x slower +219.36 μs
multi_request (non-literals, reusing ref)         2.58 K - 2.73x slower +245.34 μs
multi_request (non-literals, persistent)          2.34 K - 3.01x slower +284.78 μs
multi_request (non-literals, default opts)        2.00 K - 3.52x slower +357.78 μs
multi_request (non-literals, details)             1.70 K - 4.15x slower +446.38 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)            133.82 μs      152.10 μs        31.43 K                141.82 μs
multi_request (literals, persistent)             168.60 μs      189.94 μs        26.82 K     174.12 μs, 173.02 μs
multi_request (literals, default opts)           231.78 μs      279.95 μs        17.93 K                250.79 μs
multi_request (literals, details)                277.84 μs      513.75 μs        13.24 K310.81 μs, 352.33 μs, 355
multi_request (non-literals, reusing ref)        362.18 μs      435.68 μs        12.30 K370.87 μs, 370.48 μs, 373
multi_request (non-literals, persistent)         400.72 μs      472.18 μs        11.20 K                415.45 μs
multi_request (non-literals, default opts)       469.44 μs      551.53 μs         8.32 K502.76 μs, 479.47 μs, 509
multi_request (non-literals, details)            543.09 μs      683.70 μs         6.93 K589.11 μs, 563.87 μs, 594

##### With input 3 buckets (small atomic) #####
Name                                                 ips        average  deviation         median         99th %
multi_request (literals, reusing ref)            10.20 K       98.06 μs     ±3.31%       97.75 μs      106.55 μs
multi_request (literals, persistent)              7.80 K      128.15 μs     ±2.49%      127.68 μs      136.35 μs
multi_request (literals, default opts)            4.90 K      204.15 μs     ±2.48%      204.49 μs      215.93 μs
multi_request (literals, details)                 3.42 K      292.14 μs    ±10.75%      282.57 μs      383.43 μs
multi_request (non-literals, reusing ref)         3.20 K      312.82 μs     ±2.17%      311.69 μs      331.24 μs
multi_request (non-literals, persistent)          2.90 K      345.35 μs     ±1.65%      344.89 μs      361.04 μs
multi_request (non-literals, default opts)        2.35 K      425.18 μs     ±1.46%      424.81 μs      445.23 μs
multi_request (non-literals, details)             1.90 K      525.18 μs     ±5.14%      518.23 μs      617.92 μs

Comparison: 
multi_request (literals, reusing ref)            10.20 K
multi_request (literals, persistent)              7.80 K - 1.31x slower +30.10 μs
multi_request (literals, default opts)            4.90 K - 2.08x slower +106.09 μs
multi_request (literals, details)                 3.42 K - 2.98x slower +194.08 μs
multi_request (non-literals, reusing ref)         3.20 K - 3.19x slower +214.77 μs
multi_request (non-literals, persistent)          2.90 K - 3.52x slower +247.29 μs
multi_request (non-literals, default opts)        2.35 K - 4.34x slower +327.13 μs
multi_request (non-literals, details)             1.90 K - 5.36x slower +427.13 μs

Extended statistics: 

Name                                               minimum        maximum    sample size                     mode
multi_request (literals, reusing ref)             90.80 μs      107.75 μs        48.23 K                 97.29 μs
multi_request (literals, persistent)             120.41 μs      137.50 μs        37.05 K                125.66 μs
multi_request (literals, default opts)           188.10 μs      221.41 μs        21.22 K     207.25 μs, 205.25 μs
multi_request (literals, details)                204.43 μs      390.67 μs        15.19 K                275.07 μs
multi_request (non-literals, reusing ref)        299.43 μs      332.90 μs        14.44 K                310.62 μs
multi_request (non-literals, persistent)         331.65 μs      362.76 μs        12.93 K                344.88 μs
multi_request (non-literals, default opts)       407.53 μs      452.14 μs         9.15 K     424.63 μs, 424.30 μs
multi_request (non-literals, details)            481.33 μs      626.53 μs         7.70 K522.09 μs, 499.81 μs, 512
```