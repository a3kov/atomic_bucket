defmodule AtomicBucket.FixedCostLimiter do
  @moduledoc """
  Applies fixed cost limit: all requests to the same bucket use same
  (positive) cost.

  ## Options

  See `__using__/1`.

  ## Examples

      defmodule MyRateLimiter do
        use AtomicBucket.FixedCostLimiter
      end

      # application.ex
      children = [.., MyRateLimiter, ..]

      defmodule CallerModule do
        require MyRateLimiter

        MyRateLimiter.request(:mybucket, 1, 10, 3)
      end

  """
  @moduledoc since: "0.5.0"
  import AtomicBucket
  alias AtomicBucket.FixedCostLimiter

  @doc """
  Checks if the request is allowed according to desired rate assuming
  all requests have same cost.

  The bucket is initialized in full state. Every request will refill
  the bucket if needed and check if the new token amount is enough
  to make the request. On success the request tokens are removed from
  the bucket and the function returns `{:allow, requests, bucket_ref}`
  where requests is the number of possible additional requests based
  on the remaining tokens in the bucket. Otherwise, the bucket is left
  untouched and the function returns `{:deny, timeout, bucket_ref}`
  where timeout is estimated period in ms after which the request may
  be allowed, according to the bucket state and the refill rate.
  `bucket_ref` is a reference to the bucket atomic.

  ## Arguments:
    - `bucket_id` bucket id, unique within its table

    - `window` defines window in seconds

    - `requests` number of allowed requests in the window,
      according to the target rate. Together with window defines
      refill rate of the bucket

    - `burst` number of burst requests. Defines bucket
      capacity. Bursts ignore target request rate, and thus may
      significantly alter effective rate

  ## Options:
    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of refetching.
  """
  @doc group: "Generated API"
  @macrocallback request(
                   bucket_id :: any(),
                   window :: pos_integer(),
                   requests :: pos_integer(),
                   burst :: pos_integer(),
                   opts :: keyword()
                 ) ::
                   {:allow, requests :: non_neg_integer(), :atomics.atomics_ref()}
                   | {:deny, timeout :: timeout(), :atomics.atomics_ref()}

  @doc """
  Starts AtomicBucket server managing buckets for the limiter.

  Normally users don't need to call this function directly - instead
  the implementing module can be added to a supervision tree and
  the server is then started by a supervisor.
  """
  @doc group: "Generated API"
  @callback start_link() :: GenServer.on_start()

  def _request(id, table, window, requests, burst, persistent, idle_p, opts, env) do
    with {:ok, w} <- expand_int(window, "window", env, true),
         {:ok, r} <- expand_int(requests, "requests", env, true),
         {:ok, b} <- expand_int(burst, "burst", env, true) do
      {capacity, refill, cost} = fixed_cost_params(w, r, b, idle_p)

      quote do
        AtomicBucket._validated_req(
          unquote(id),
          unquote(table),
          unquote(capacity),
          unquote(refill),
          unquote(cost),
          unquote(persistent),
          unquote(opts)
        )
      end
    else
      _ ->
        quote do
          AtomicBucket._unvalidated_req(
            unquote(id),
            unquote(table),
            unquote(window),
            unquote(requests),
            unquote(burst),
            unquote(persistent),
            unquote(idle_p),
            unquote(opts)
          )
        end
    end
  end

  @doc """
  Converts the current module to a fixed cost rate limiter:
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
      @behaviour FixedCostLimiter

      validated_rate_limiter_opts(opts, __MODULE__)
      |> set_rate_limiter_attributes(__MODULE__)

      @impl true
      defmacro request(bucket_id, window, requests, burst, opts \\ []) do
        FixedCostLimiter._request(
          bucket_id,
          @atomic_bucket_table,
          window,
          requests,
          burst,
          @atomic_bucket_persistent,
          @atomic_bucket_max_idle_period,
          opts,
          __CALLER__
        )
      end

      @impl true
      def start_link() do
        AtomicBucket.start_link(
          type: FixedCostLimiter,
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
