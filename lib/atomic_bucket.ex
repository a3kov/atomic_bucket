defmodule AtomicBucket do
  @moduledoc """
  Fast single node rate limiter implementing Token Bucket algorithm.
  """
  use GenServer

  @token_bits 31
  @timer_bits 32
  @max_window div(Integer.pow(2, 31), 1000)
  @timer_modulus Integer.pow(2, @timer_bits)
  @default_cleanup_interval :timer.hours(1)
  @default_max_idle_period :timer.hours(24)

  @doc """
  Checks if the request is allowed according to desired request rate.

  The bucket is initialized in full state. Every request will refill
  the bucket if needed and check if the new token amount is enough
  to make the request. On success the function returns
  `{:allow, requests, bucket_ref}` where requests is the number of possible
  additional requests based on the remaining tokens in the bucket.
  Otherwise, the bucket is left untouched and the function returns
  `{:deny, timeout, bucket_ref}` where timeout is estimated interval in ms
  after which the request may be allowed, according to the bucket state and
  refill rate.
  `bucket_ref` is a reference to the bucket atomic, which can be used by
  long running processes instead of the bucket name for better performance.

  Arguments:
    - `bucket` - bucket id, unique within its table
    - `window` defines window in seconds
    - `window_requests` number of allowed requests in the window. Together
      with window defines refill rate
    - `burst_requests` - number of burst requests. Defines bucket
      capacity. Bursts ignore target request rate, and thus may
      significantly alter effective rate.

  Supported options:
    - `persistent` if true, the bucket reference is also cached in
      `:persistent_term`. Default is false.

    - `ref` bucket atomic reference. If provided, the call will try
      to use it instead of fetching the ref from ETS or :persistent_term.

    - `table` ETS table name atom. Default is AtomicBucket module name.
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
    with {:ok, w} <- eval_const(window, "window", __CALLER__),
         {:ok, r} <- eval_const(window_requests, "window_requests", __CALLER__),
         {:ok, b} <- eval_const(burst_requests, "burst_requests", __CALLER__) do
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
      :not_constant ->
        quote do
          AtomicBucket.__unvalidated_request__(
            unquote(bucket),
            unquote(window),
            unquote(window_requests),
            unquote(burst_requests),
            unquote(opts)
          )
        end

      {:invalid_literal, name} ->
        int_arg_error(name)
    end
  end

  defp eval_const(value, _name, _env) when is_integer(value) and value >= 0, do: {:ok, value}

  defp eval_const({:@, _, [{attr, _, _}]}, name, env) do
    # value = Module.get_attribute(env.module, attr)
    value = env.module.__info__(:attributes)[attr]

    if is_integer(value) && value >= 0 do
      {:ok, value}
    else
      {:invalid_literal, name}
    end
  end

  defp eval_const(value, name, _env) do
    if Macro.quoted_literal?(value) do
      {:invalid_literal, name}
    else
      :not_constant
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
      raise ArgumentError, "Window is bigger than the max value (#{@max_window})."
    end

    window_ms = window * 1000
    cost = div(window_ms, Integer.gcd(requests, window_ms))
    refill = div(requests * cost, window_ms)
    capacity = burst_requests * cost

    if capacity > Integer.pow(2, @token_bits) - 1 do
      error =
        """
        Required bucket capacity of #{capacity} can't fit in #{@token_bits} token bits. \
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
      new_atomic = encode_bucket(timer, tokens_after_request, 0)

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
      bucket_ref = Keyword.get(opts, :ref, nil) ->
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

    case decode_bucket(atomic) do
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
    atomic = encode_bucket(timer, capacity, 0)
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

  defp encode_bucket(timer, tokens, deleted) do
    <<atomic::signed-integer-size(64)>> =
      <<timer::integer-size(@timer_bits), tokens::integer-size(@token_bits),
        deleted::integer-size(1)>>

    atomic
  end

  defp decode_bucket(atomic) do
    <<
      timer::integer-size(@timer_bits),
      tokens::integer-size(@token_bits),
      deleted::integer-size(1)
    >> = <<atomic::signed-integer-size(64)>>

    {timer, tokens, deleted}
  end

  @doc """
  Starts the process manages ETS table holding bucket references and periodically
  removes idle bucket references.

  In addition to standard GenServer options, accepts the following:
    - `:cleanup_interval` interval in ms defining how often the server will try
      to delete idle buckets. Default is 1 hour.

    - `:max_idle_period` max period in ms since last allowed request before
      the bucket is deleted. Default is 24hours.

    - `table` ETS table name atom. Default is AtomicBucket module name.
  """
  def start_link(opts) do
    {gen_opts, opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    max_idle_period = Keyword.get(opts, :max_idle_period, @default_max_idle_period)

    :ets.new(table, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    schedule_gc(cleanup_interval)

    {:ok, %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period}}
  end

  @impl true
  def handle_info(:run_gc, state) do
    %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period} = state
    timer = wrapping_timer()

    :ets.foldl(
      fn {bucket, bucket_ref}, acc ->
        atomic = :atomics.get(bucket_ref, 1)
        {prev_timer, tokens, 0} = decode_bucket(atomic)

        if wrapping_timer_delta(prev_timer, timer) > max_idle_period do
          new_atomic = encode_bucket(prev_timer, tokens, 1)

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

    schedule_gc(cleanup_interval)

    {:noreply, state}
  end

  defp schedule_gc(cleanup_interval) do
    Process.send_after(self(), :run_gc, cleanup_interval)
  end
end
