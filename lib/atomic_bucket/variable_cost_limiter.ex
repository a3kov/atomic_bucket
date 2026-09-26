defmodule AtomicBucket.VariableCostLimiter do
  @moduledoc """
  Applies variable cost limit: requests to the same bucket may use
  different (including zero and negative) cost.

  ## Options

  See `__using__/1`.

  ## Examples

      defmodule MyRateLimiter do
        use AtomicBucket.VariableCostLimiter
      end

      # application.ex
      children = [.., MyRateLimiter, ..]

      defmodule CallerModule do
        require MyRateLimiter

        MyRateLimiter.request(:mybucket, 200, 1, 100)
      end
  """
  @moduledoc since: "0.5.0"
  import AtomicBucket
  alias AtomicBucket.VariableCostLimiter

  @doc """
  Checks if the request is allowed according to bucket parameters.

  Supports variable (including zero and negative) cost.

  The bucket is initialized in full state. Every request will refill
  the bucket if needed and check if the new token amount with the cost applied
  is valid (not negative). Tokens above the capacity are discarded.

  Returns `{:allow, tokens, bucket_ref}` or `{:deny, tokens, bucket_ref}`
  where `tokens` is the number of remaining tokens in the bucket.

  ## Arguments:
    - `bucket_id` bucket id, unique within its table

    - `capacity` bucket capacity

    - `refill_ms` number of tokens added to the bucket every millisecond

    - `cost` number of tokens added or removed from the bucket for the current
      request to succeed, where negative values mean addition

  ## Options:
    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of refetching.
  """
  @doc group: "Generated API"
  @macrocallback request(
                   bucket_id :: any(),
                   capacity :: pos_integer(),
                   refill_ms :: pos_integer(),
                   cost :: integer(),
                   opts :: keyword()
                 ) ::
                   {AtomicBucket.verdict(), tokens :: non_neg_integer(), :atomics.atomics_ref()}

  @doc """
  Starts AtomicBucket server managing buckets for the limiter.

  Normally users don't need to call this function directly - instead
  the implementing module can be added to a supervision tree and
  the server is then started by a supervisor.
  """
  @doc group: "Generated API"
  @callback start_link() :: GenServer.on_start()

  def _request(id, table, capacity, refill_ms, cost, persistent, opts, env) do
    with {:ok, cap_int} <- expand_int(capacity, "capacity", env, true),
         {:ok, ref_int} <- expand_int(refill_ms, "refill_ms", env, true),
         {:ok, cost_int} <- expand_int(cost, "cost", env) do
      validate_raw_params!(cap_int, ref_int, cost_int)

      quote do
        AtomicBucket._validated_raw_req(
          unquote(id),
          unquote(table),
          unquote(cap_int),
          unquote(ref_int),
          unquote(cost_int),
          unquote(persistent),
          unquote(opts)
        )
      end
    else
      _ ->
        quote do
          AtomicBucket._unvalidated_raw_req(
            unquote(id),
            unquote(table),
            unquote(capacity),
            unquote(refill_ms),
            unquote(cost),
            unquote(persistent),
            unquote(opts)
          )
        end
    end
  end

  @doc """
  Converts the current module to a variable cost rate limiter:
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
      @behaviour VariableCostLimiter

      validated_rate_limiter_opts(opts, __MODULE__)
      |> set_rate_limiter_attributes(__MODULE__)

      @impl true
      defmacro request(bucket_id, capacity, refill_ms, cost, opts \\ []) do
        VariableCostLimiter._request(
          bucket_id,
          @atomic_bucket_table,
          capacity,
          refill_ms,
          cost,
          @atomic_bucket_persistent,
          opts,
          __CALLER__
        )
      end

      @impl true
      def start_link() do
        AtomicBucket.start_link(
          type: VariableCostLimiter,
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
