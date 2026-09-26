defmodule AtomicBucket.MultiRateLimiter do
  @moduledoc """
  Applies multiple rate limits at the same time, in a single atomic
  operation.

  ## Options

  See `__using__/1`.

  ## Examples

      defmodule MyRateLimiter do
        use AtomicBucket.MultiRateLimiter
      end

      # application.ex
      children = [.., MyRateLimiter, ..]

      defmodule CallerModule do
        require MyRateLimiter

        @sub_buckets %{
          second: {330, 2},
          minute: {3_000, 7},
          hour: {60_000, 30}
        }

        MyRateLimiter.request(:mybucket, @sub_buckets)

        # Or with details.
        MyRateLimiter.request_details(:mybucket, @sub_buckets)
      end
  """
  @moduledoc since: "0.5.0"
  import AtomicBucket
  alias AtomicBucket.MultiRateLimiter

  @doc """
  Checks if the request is allowed according to multiple rate limits.

  Uses simplified algorithm, where each rate is represented as
  request interval in milliseconds instead of window and requests.
  The bucket is updated in a single atomic operation. By default fixed
  request cost is assumed, but variable cost is also supported via
  cost factor.

  Multiple buckets are initialized in full state. Every request will
  refill each bucket if needed and check if all buckets have enough
  tokens to make the request. If true, the request tokens are
  removed from each bucket and the call returns `{:allow, bucket_ref}`.
  Otherwise, each bucket is left untouched and the call returns
  `{:deny, bucket_ref}`. `bucket_ref` is a reference to the bucket
  atomic.

  There must be no duplicate intervals inside the sub-buckets, and lower
  rate buckets must have bigger bursts (otherwise they kick in too soon).

  ## Arguments:
    - `bucket_id` any id unique within the bucket table

    - `sub_buckets` a map describing sub-buckets, with sub-bucket
      names as keys and `{request interval in milliseconds, burst requests}`
      tuples as values

    - `cost_factor` integer multiplier for the request cost

  ## Options:
    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of refetching.
  """
  @doc group: "Generated API"
  @macrocallback request(
                   bucket_id :: any(),
                   sub_buckets :: %{
                     (name :: atom()) =>
                       {request_interval :: pos_integer(), burst :: pos_integer()}
                   },
                   cost_factor :: integer(),
                   opts :: keyword()
                 ) :: {AtomicBucket.verdict(), :atomics.atomics_ref()}

  @doc """
  Checks if the request is allowed according to multiple rate limits and
  returns results of each bucket check.

  Unless you *really* need the results, consider using `request/4`
  instead, which skips unnecessary calculations.

  Multiple buckets are initialized in full state. Every request will
  refill each bucket if needed and check if all buckets have enough
  tokens to make the request.
  If true, the call returns `{:allow, requests, bucket_ref}`,
  where `requests` is a map with remaining requests of each sub-bucket.
  Otherwise, each bucket is left untouched and the call returns
  `{:deny, results, bucket_ref}`, where `results` is a map with sub-bucket
  name keys and result tuples (`{:allow, remaining requests}` or
  `{:deny, timeout}`) as values.

  Note that remaining requests in the result tuple reflect final number
  of available requests in the sub-bucket after the call.

  There must be no duplicate intervals inside the sub-buckets, and lower
  rate buckets must have bigger bursts (otherwise they kick in too soon).

  ## Arguments:
    - `bucket_id` any id unique within the bucket table

    - `sub_buckets` a map describing sub-buckets, with sub-bucket
      names as keys and `{request interval in milliseconds, burst requests}`
      tuples as values.

    - `cost_factor` integer multiplier for the request cost

  ## Options:
    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of refetching.
  """
  @doc group: "Generated API"
  @macrocallback request_details(
                   bucket_id :: any(),
                   sub_buckets :: %{
                     (name :: atom()) =>
                       {request_interval :: pos_integer(), burst :: pos_integer()}
                   },
                   cost_factor :: integer(),
                   opts :: keyword()
                 ) ::
                   {:allow, %{(name :: any()) => non_neg_integer()}, :atomics.atomics_ref()}
                   | {:deny, %{(name :: any()) => {AtomicBucket.verdict(), non_neg_integer()}},
                      :atomics.atomics_ref()}

  @doc """
  Starts AtomicBucket server managing buckets for the limiter.

  Normally users don't need to call this function directly - instead
  the implementing module can be added to a supervision tree and
  the server is then started by a supervisor.
  """
  @doc group: "Generated API"
  @callback start_link() :: GenServer.on_start()

  def _request(id, table, sub_buckets, cost_factor_ast, pers, opts, details?, env) do
    buckets = Macro.expand(sub_buckets, env)
    cost_factor = Macro.expand(cost_factor_ast, env)

    if Macro.quoted_literal?(buckets) && Macro.quoted_literal?(cost_factor) do
      if !is_integer(cost_factor), do: int_arg_error!("cost_factor")
      {:%{}, _, bucket_list} = buckets
      {buckets, token_interval} = multi_params(bucket_list, cost_factor)
      buckets_ast = Enum.map(buckets, fn {k, v} -> {k, Macro.escape(v)} end)

      if details? do
        quote do
          AtomicBucket._multi_req_details(
            unquote(id),
            unquote(table),
            unquote(buckets_ast),
            unquote(token_interval),
            unquote(cost_factor),
            unquote(pers),
            unquote(opts)
          )
        end
      else
        quote do
          AtomicBucket._multi_req(
            unquote(id),
            unquote(table),
            unquote(buckets_ast),
            unquote(token_interval),
            unquote(cost_factor),
            unquote(pers),
            unquote(opts)
          )
        end
      end
    else
      if details? do
        quote do
          AtomicBucket._unvalidated_multi_req_details(
            unquote(id),
            unquote(table),
            unquote(buckets),
            unquote(cost_factor_ast),
            unquote(pers),
            unquote(opts)
          )
        end
      else
        quote do
          AtomicBucket._unvalidated_multi_req(
            unquote(id),
            unquote(table),
            unquote(buckets),
            unquote(cost_factor_ast),
            unquote(pers),
            unquote(opts)
          )
        end
      end
    end
  end

  @doc """
  Converts the current module to a multi-rate limiter:
    - generates rate limiter API

    - adds AtomicBucket server child spec so that the module can be added
      to a supervision tree

  This macro does only basic validation of the cleanup parameters.
  Developers must ensure that buckets idling for more than ~24 days
  are deleted: longer periods are not supported by the wrapping timer
  used by the library.

  ## Options:
    - `:table` ETS table name atom. By default is implementing module name.

    - `:cleanup_interval` interval in ms defining how often the server will try
      to delete idle buckets. It is applied on completion of a cleanup.
      Default is 1 hour.

    - `:max_idle_period` max period in ms since last bucket update before
      it is deleted by the server. Default is 24 hours.

    - `persistent` if true, bucket references will be cached in
      `:persistent_term`. Default is false.
  """
  defmacro __using__(opts \\ []) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour MultiRateLimiter

      validated_rate_limiter_opts(opts, __MODULE__)
      |> set_rate_limiter_attributes(__MODULE__)

      @impl true
      defmacro request(bucket_id, sub_buckets, cost_factor \\ 1, opts \\ []) do
        MultiRateLimiter._request(
          bucket_id,
          @atomic_bucket_table,
          sub_buckets,
          cost_factor,
          @atomic_bucket_persistent,
          opts,
          false,
          __CALLER__
        )
      end

      @impl true
      defmacro request_details(bucket_id, sub_buckets, cost_factor \\ 1, opts \\ []) do
        MultiRateLimiter._request(
          bucket_id,
          @atomic_bucket_table,
          sub_buckets,
          cost_factor,
          @atomic_bucket_persistent,
          opts,
          true,
          __CALLER__
        )
      end

      @impl true
      def start_link() do
        AtomicBucket.start_link(
          type: MultiRateLimiter,
          name: __MODULE__,
          table: @atomic_bucket_table,
          cleanup_interval: @atomic_bucket_cleanup_interval,
          max_idle_period: @atomic_bucket_max_idle_period,
          persistent: @atomic_bucket_persistent
        )
      end

      @doc false
      def child_spec(_init_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []}
        }
      end
    end
  end
end
