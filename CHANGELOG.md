# Changelog

## v0.5.0 (2026-09-27)

Breaking changes:
 - rate limiter modules generate own macros that replace global macros

 - rate limiter options replace global macro options and server options as the main
   form of configuration

 - each rate limiter module provides child spec for starting AtomicBucket server
   managing its buckets

 - `persistent` is now a parameter of rate limiter module, affecting all of its
   buckets

 - `raw_request` and `multi_request` macros are now simply `request`

 - multi-bucket `details` option converted to a separate `request_details` macro

## v0.4.1 (2026-09-21)

Improve validation of sub-bucket rates.
Move benchmark support file out of the project.
Set process labels for AtomicBucket servers.

## v0.4.0 (2026-09-20)

Requires Elixir >=1.17 and Erlang >=27.
New feature: enforce multiple rate limits in a single operation via multi_request/4.
Lazy refills in raw_request/5.
Move bucket cleanup procedure to a task for easy gc.
Improve performance of the cleanup procedure.
Fix flaky tests.
Improve docs.

## v0.3.1 (2026-08-16)

Create unique server id in child spec based on the table for easier inclusion
of multiple servers in application children.

## v0.3.0 (2026-08-12)

20-30% performance gain for normal size buckets on 64bit.
Benchmarking improvements.

## v0.2.0 (2026-06-07)

Add support for variable cost and token "refunds" via raw_request/5

## v0.1.3 (2026-02-10)

Fix: bucket reference passed instead of bucket id in do_params_request/5

## v0.1.2 (2026-02-08)

More docs improvements

## v0.1.1 (2026-02-07)

Minor improvements and docs updates

## v0.1.0 (2026-02-06)

Initial Release
