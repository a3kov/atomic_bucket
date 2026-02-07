defmodule AtomicBucket do
  @moduledoc """
  Fast single node rate limiter implementing Token Bucket algorithm.
  """
  use GenServer

  import Bitwise

  @token_bits 31
  @timer_bits 32
  @max_window div(1 <<< 31, 1000)
  @max_capacity (1 <<< @token_bits) - 1
  @timer_modulus 1 <<< @timer_bits
  @default_cleanup_interval :timer.hours(1)
  @default_max_idle_period :timer.hours(24)

  @doc """
  Checks if the request is allowed according to desired request rate.

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

  Arguments:
    - `bucket` bucket id, unique within its table
    - `window` defines window in seconds
    - `window_requests` number of allowed requests in the window,
      according to the target rate. Together with window defines
      refill rate of the bucket.
    - `burst_requests` number of burst requests. Defines bucket
      capacity. Bursts ignore target request rate, and thus may
      significantly alter effective rate.

  Supported options:
    - `persistent` if true, the bucket reference is also cached in
      `:persistent_term`. Default is false.

    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of refetching.

    - `table` ETS table name atom. Default is AtomicBucket.
  """
  @spec request(
          bucket :: any(),
          window :: pos_integer(),
          window_requests :: pos_integer(),
          burst_requests :: pos_integer(),
          opts :: keyword()
        ) ::
          {:allow, bucket_requests :: pos_integer(), :atomics.atomics_ref()}
          | {:deny, timeout :: timeout(), :atomics.atomics_ref()}

  defmacro request(bucket, window, window_requests, burst_requests, opts \\ []) do
    with {:ok, w} <- expand_pos_int(window, "window", __CALLER__),
         {:ok, r} <- expand_pos_int(window_requests, "window_requests", __CALLER__),
         {:ok, b} <- expand_pos_int(burst_requests, "burst_requests", __CALLER__) do
      {capacity, refill, cost} = validated_bucket_params(w, r, b)

      quote do
        AtomicBucket.__bucket_params_request__(
          unquote(bucket),
          unquote(capacity),
          unquote(refill),
          unquote(cost),
          unquote(opts)
        )
      end
    else
      _ ->
        quote do
          AtomicBucket.__unvalidated_request__(
            unquote(bucket),
            unquote(window),
            unquote(window_requests),
            unquote(burst_requests),
            unquote(opts)
          )
        end
    end
  end

  defp expand_pos_int(ast, name, env) do
    value = Macro.expand(ast, env)

    cond do
      is_integer(value) and value > 0 ->
        {:ok, value}

      Macro.quoted_literal?(value) ->
        int_arg_error(name)

      true ->
        :error
    end
  end

  def __unvalidated_request__(bucket, window, requests, burst_requests, opts) do
    {capacity, refill, cost} = validated_bucket_params(window, requests, burst_requests)
    do_params_request(bucket, capacity, refill, cost, opts)
  end

  def __bucket_params_request__(bucket, capacity, refill, cost, opts) do
    do_params_request(bucket, capacity, refill, cost, opts)
  end

  defp validated_bucket_params(window, requests, burst_requests) do
    if !pos_int?(window), do: int_arg_error("window")
    if !pos_int?(requests), do: int_arg_error("window_requests")
    if !pos_int?(burst_requests), do: int_arg_error("burst_requests")

    if window > @max_window do
      raise ArgumentError, "Window is above the limit (#{@max_window})."
    end

    window_ms = window * 1000
    cost = div(window_ms, Integer.gcd(requests, window_ms))
    refill = div(requests * cost, window_ms)
    capacity = burst_requests * cost

    if capacity > @max_capacity do
      error =
        """
        Required bucket capacity (#{capacity}) is above the limit (#{@max_capacity}). \
        Consider adjusting window size, requests or burst requests.
        """

      raise ArgumentError, error
    end

    {capacity, refill, cost}
  end

  defp pos_int?(value), do: is_integer(value) && value > 0

  defp int_arg_error(name) do
    raise ArgumentError, "Invalid argument: #{name} must be a positive integer."
  end

  defp do_params_request(bucket, capacity, refill_ms, cost, opts) do
    timer = wrapping_timer()
    {bucket_ref, atomic, prev_timer, tokens} = get_bucket(bucket, capacity, opts)

    tokens_after_refill =
      min(capacity, tokens + refill_ms * wrapping_timer_delta(prev_timer, timer))

    tokens_after_request = tokens_after_refill - cost

    if tokens_after_request >= 0 do
      new_atomic = pack_bucket(timer, tokens_after_request, 0)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, div(tokens_after_request, cost), bucket_ref}

        _ ->
          do_params_request(bucket_ref, capacity, refill_ms, cost, opts)
      end
    else
      timeout = div(cost - tokens_after_refill, refill_ms)
      {:deny, timeout, bucket_ref}
    end
  end

  defp get_bucket(bucket, capacity, opts) do
    cond do
      bucket_ref = Keyword.get(opts, :ref) ->
        open_bucket(bucket_ref, bucket, capacity, opts)

      bucket_ref = persistent_bucket?(opts) && pt_get(bucket, opts) ->
        open_bucket(bucket_ref, bucket, capacity, opts)

      true ->
        case :ets.lookup(table(opts), bucket) do
          [{_, bucket_ref}] ->
            open_bucket(bucket_ref, bucket, capacity, opts)

          [] ->
            try_create_bucket(bucket, capacity, opts)
        end
    end
  end

  defp open_bucket(bucket_ref, bucket, capacity, opts) do
    atomic = :atomics.get(bucket_ref, 1)

    case unpack_bucket(atomic) do
      {timer, tokens, 0} ->
        {bucket_ref, atomic, timer, tokens}

      _ ->
        # When deleting buckets, after updating the atomic the server will
        # delete references to it, and eventually some process (or the
        # current one) will succeed in recreating it, if we keep retrying.
        # We make sure this is not a reference passed via options, so that
        # we don't get stuck in eternal loop.
        opts = Keyword.drop(opts, [:ref])
        get_bucket(bucket, capacity, opts)
    end
  end

  defp try_create_bucket(bucket, capacity, opts) do
    table = table(opts)
    bucket_ref = :atomics.new(1, [])
    timer = wrapping_timer()
    atomic = pack_bucket(timer, capacity, 0)
    :atomics.put(bucket_ref, 1, atomic)

    if :ets.insert_new(table, {bucket, bucket_ref}) do
      if persistent_bucket?(opts) do
        :persistent_term.put(pt_bucket_key(table, bucket), bucket_ref)
      end

      {bucket_ref, atomic, timer, capacity}
    else
      get_bucket(bucket, capacity, opts)
    end
  end

  defp persistent_bucket?(opts), do: Keyword.get(opts, :persistent, false)

  defp pt_get(bucket, opts) do
    table(opts)
    |> pt_bucket_key(bucket)
    |> :persistent_term.get(nil)
  end

  defp table(opts), do: Keyword.get(opts, :table, __MODULE__)

  defp pt_bucket_key(table, bucket), do: {__MODULE__, table, bucket}

  defp wrapping_timer() do
    rem = rem(System.monotonic_time(:millisecond), @timer_modulus)
    if rem < 0, do: rem + @timer_modulus, else: rem
  end

  defp wrapping_timer_delta(timer1, timer2) do
    delta = timer2 - timer1
    if delta >= 0, do: delta, else: delta + @timer_modulus
  end

  defp pack_bucket(timer, tokens, deleted) do
    <<atomic::signed-integer-size(64)>> =
      <<timer::integer-size(@timer_bits), tokens::integer-size(@token_bits),
        deleted::integer-size(1)>>

    atomic
  end

  defp unpack_bucket(atomic) do
    <<
      timer::integer-size(@timer_bits),
      tokens::integer-size(@token_bits),
      deleted::integer-size(1)
    >> = <<atomic::signed-integer-size(64)>>

    {timer, tokens, deleted}
  end

  @doc """
  Starts the process that manages ETS table for bucket data and
  periodically deletes idle buckets.

  The function does only basic validation of the cleanup parameters.
  Developers must ensure that buckets idling for more than ~24 days
  are deleted: longer periods are not supported by the wrapping timer
  used by the library.

  In addition to standard GenServer options, accepts the following:
    - `:cleanup_interval` interval in ms defining how often the server will try
      to delete idle buckets. Default is 1 hour.

    - `:max_idle_period` max period in ms since last allowed request before
      the bucket is deleted. Default is 24 hours.

    - `table` ETS table name atom. Default is AtomicBucket.
  """
  def start_link(opts) do
    {gen_opts, opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    validate_cleanup_arg!(:cleanup_interval, cleanup_interval(opts))
    validate_cleanup_arg!(:max_idle_period, max_idle_period(opts))

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  defp validate_cleanup_arg!(name, value) do
    max_window_ms = @max_window * 1000

    if !is_integer(value) || value <= 0 || value >= max_window_ms do
      raise ArgumentError, "#{name} must be a positive integer less than #{max_window_ms}"
    end
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__)
    cleanup_interval = cleanup_interval(opts)
    max_idle_period = max_idle_period(opts)

    :ets.new(table, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    schedule_cleanup(cleanup_interval)

    {:ok, %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period}}
  end

  defp cleanup_interval(opts), do: Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)

  defp max_idle_period(opts), do: Keyword.get(opts, :max_idle_period, @default_max_idle_period)

  @impl true
  def handle_info(:cleanup, state) do
    %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period} = state

    :ets.foldl(
      fn {bucket, bucket_ref}, acc ->
        atomic = :atomics.get(bucket_ref, 1)
        {prev_timer, tokens, 0} = unpack_bucket(atomic)
        timer = wrapping_timer()

        if wrapping_timer_delta(prev_timer, timer) > max_idle_period do
          new_atomic = pack_bucket(prev_timer, tokens, 1)

          case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
            :ok ->
              :ets.delete_object(table, {bucket, bucket_ref})
              :persistent_term.erase(pt_bucket_key(table, bucket))
              acc + 1

            _ ->
              acc
          end
        else
          acc
        end
      end,
      0,
      table
    )

    schedule_cleanup(cleanup_interval)

    {:noreply, state}
  end

  defp schedule_cleanup(cleanup_interval) do
    Process.send_after(self(), :cleanup, cleanup_interval)
  end
end
