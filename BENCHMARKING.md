# Benchmarking

The included benchmark (`bench/benchmark.exs`) measures series of 1000 rate
limit checks. It serves as an illustration of available options. Run it like so:
```shell
mix run bench/benchmark.exs
```

There are 2 bucket types in the benchmark: normal size and monster size. Normal
size has numbers typical for rate limiters, and monster size has extreme parameters,
unlikely to be used by anyone. Monster buckets take a big performance hit
because of the way big integers are implemented in BEAM. 32bit architectures
will take a similar hit even with normal-sized buckets - for our purposes all
integers on 32bit are "big".

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
```