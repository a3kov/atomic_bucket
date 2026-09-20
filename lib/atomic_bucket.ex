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
  @detault_multi_details? false
  @default_cleanup_interval :timer.hours(1)
  @default_max_idle_period :timer.hours(24)
  @test_env? Application.compile_env(:atomic_bucket, :test_env, false)
  @compile {:inline,
            [
              validate_raw_params!: 3,
              get_bucket: 3,
              open_bucket: 4,
              try_create_bucket: 3,
              pack_bucket: 3,
              unpack_bucket: 2,
              bucket_timer: 1,
              wrapping_timer: 0,
              get_timer: 1,
              wrapping_timer_delta: 2,
              persistent_bucket?: 1,
              pos_int?: 1,
              pt_get: 2,
              pt_bucket_key: 2,
              table: 1
            ]}

  @type verdict :: :allow | :deny

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
          {:allow, bucket_requests :: non_neg_integer(), :atomics.atomics_ref()}
          | {:deny, timeout :: timeout(), :atomics.atomics_ref()}

  defmacro request(bucket, window, window_requests, burst_requests, opts \\ []) do
    with {:ok, w} <- expand_int(window, "window", __CALLER__, true),
         {:ok, r} <- expand_int(window_requests, "window_requests", __CALLER__, true),
         {:ok, b} <- expand_int(burst_requests, "burst_requests", __CALLER__, true) do
      {capacity, refill, cost} = fixed_cost_params(w, r, b)

      quote do
        AtomicBucket.__validated_request__(
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

  def __unvalidated_request__(bucket, window, requests, burst_requests, opts) do
    {capacity, refill_ms, cost} = fixed_cost_params(window, requests, burst_requests)
    __validated_request__(bucket, capacity, refill_ms, cost, opts)
  end

  def __validated_request__(bucket, capacity, refill_ms, cost, opts) do
    timer = get_timer(opts)
    {bucket_ref, atomic, prev_timer, tokens} = get_bucket(bucket, capacity, opts)

    tokens_after_refill =
      min(capacity, tokens + refill_ms * wrapping_timer_delta(prev_timer, timer))

    tokens_after_request = tokens_after_refill - cost

    if tokens_after_request >= 0 do
      new_atomic = pack_bucket(tokens_after_request, timer, capacity)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, div(tokens_after_request, cost), bucket_ref}

        _ ->
          __validated_request__(bucket, capacity, refill_ms, cost, opts)
      end
    else
      {:deny, div(cost - tokens_after_refill, refill_ms), bucket_ref}
    end
  end

  defp fixed_cost_params(window, requests, burst_requests) do
    if !pos_int?(window), do: pos_int_arg_error!("window")
    if !pos_int?(requests), do: pos_int_arg_error!("window_requests")
    if !pos_int?(burst_requests), do: pos_int_arg_error!("burst_requests")

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

  @doc """
  Checks if the request is allowed according to bucket parameters.

  Supports variable (including zero and negative) cost.

  The bucket is initialized in full state. Every request will refill
  the bucket if needed and check if the new token amount with the cost applied
  is valid (not negative). Tokens above the capacity are discarded.

  Returns `{:allow, tokens, bucket_ref}` or `{:deny, tokens, bucket_ref}`
  where `tokens` is the number of remaining tokens in the bucket.

  Arguments:
    - `bucket` bucket id, unique within its table
    - `capacity` bucket capacity
    - `refill_ms` number of tokens added to the bucket every millisecond
    - `cost` number of tokens added or removed from the bucket for the current
      request to succeed, where negative values mean addition.

  Supports same options as request/5
  """
  @spec raw_request(
          bucket :: any(),
          capacity :: pos_integer(),
          refill_ms :: pos_integer(),
          cost :: integer(),
          opts :: keyword()
        ) :: {verdict(), tokens :: non_neg_integer(), :atomics.atomics_ref()}

  defmacro raw_request(bucket, capacity, refill_ms, cost, opts \\ []) do
    with {:ok, cap_int} <- expand_int(capacity, "capacity", __CALLER__, true),
         {:ok, ref_int} <- expand_int(refill_ms, "refill_ms", __CALLER__, true),
         {:ok, cost_int} <- expand_int(cost, "cost", __CALLER__) do
      validate_raw_params!(cap_int, ref_int, cost_int)

      quote do
        AtomicBucket.__validated_raw_request__(
          unquote(bucket),
          unquote(cap_int),
          unquote(ref_int),
          unquote(cost_int),
          unquote(opts)
        )
      end
    else
      _ ->
        quote do
          AtomicBucket.__unvalidated_raw_request__(
            unquote(bucket),
            unquote(capacity),
            unquote(refill_ms),
            unquote(cost),
            unquote(opts)
          )
        end
    end
  end

  def __unvalidated_raw_request__(bucket, capacity, refill_ms, cost, opts) do
    validate_raw_params!(capacity, refill_ms, cost)
    __validated_raw_request__(bucket, capacity, refill_ms, cost, opts)
  end

  def __validated_raw_request__(bucket, capacity, refill_ms, cost, opts) do
    timer = get_timer(opts)
    {bucket_ref, atomic, prev_timer, tokens} = get_bucket(bucket, capacity, opts)
    elapsed = wrapping_timer_delta(prev_timer, timer)
    tokens_after_refill = min(capacity, tokens + refill_ms * elapsed)
    tokens_after_request = min(capacity, tokens_after_refill - cost)

    if tokens_after_request >= 0 do
      new_atomic = pack_bucket(tokens_after_request, timer, capacity)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, tokens_after_request, bucket_ref}

        _ ->
          __validated_raw_request__(bucket, capacity, refill_ms, cost, opts)
      end
    else
      {:deny, tokens_after_refill, bucket_ref}
    end
  end

  defp validate_raw_params!(capacity, refill_ms, cost) do
    if !pos_int?(capacity), do: pos_int_arg_error!("capacity")
    if !pos_int?(refill_ms), do: pos_int_arg_error!("refill_ms")
    if !is_integer(cost), do: int_arg_error!("cost")

    if capacity > @max_capacity do
      raise ArgumentError, "Capacity is above the limit (#{@max_capacity})."
    end

    if refill_ms >= capacity do
      raise ArgumentError, "refill_ms must be less than capacity."
    end

    if abs(cost) > capacity do
      raise ArgumentError, "cost can't exceed capacity."
    end
  end

  @doc """
  Checks if the request is allowed according to multiple rate limits.
  By default fixed request cost is assumed, but variable cost is also
  supported via cost factor.

  Uses simplified algorithm, where each rate is represented as
  request interval in milliseconds instead of window and requests.
  The bucket is updated in a single atomic operation.

  Multiple buckets are initialized in full state. Every request will
  refill each bucket if needed and check if all buckets have enough
  tokens to make the request. On success the request tokens are
  removed from each bucket and the call returns `{:allow, bucket_ref}`.
  Otherwise, each bucket is left untouched and the call returns
  `{:deny, bucket_ref}`. `bucket_ref` is a reference to the bucket
  atomic.

  Arguments:
    - `bucket_id` any id unique within the bucket table
    - `sub_buckets` a map describing sub-buckets, with sub-bucket
      names as keys and `{request interval in milliseconds, burst requests}`
      tuples as values.
    - `cost_factor` integer multiplier for the request cost

  Supports same options as `request/5`, plus:
    - `:details` - whether to return info about sub-bucket state (boolean).
      If true, the call returns either `{:allow, requests, bucket_ref}`,
      where `requests` is a map with remaining requests of each sub-bucket,
      or `{:deny, results, bucket_ref}`, where `results` is a map with
      sub-bucket name keys and result tuples (`{:allow, remaining requests}`
      or `{:deny, timeout}`) as values.
      If false (default value), only basic verdict is returned.
      Disabled details skip unnecessary calculations, and turning them on
      has big impact on performance of the operation.
      Note that remaining requests in the result tuple reflect final number
      of available requests in the sub-bucket after the call.
  """
  @spec multi_request(
          bucket_id :: any(),
          sub_buckets :: %{
            (name :: atom()) => {request_interval :: pos_integer(), burst :: pos_integer()}
          },
          cost_factor :: integer(),
          opts :: keyword()
        ) ::
          {verdict(), :atomics.atomics_ref()}
          | {:allow, %{(name :: any()) => non_neg_integer()}, :atomics.atomics_ref()}
          | {:deny, %{(name :: any()) => {verdict(), non_neg_integer()}}, :atomics.atomics_ref()}

  defmacro multi_request(bucket_id, sub_buckets, cost_factor \\ 1, opts \\ []) do
    buckets = Macro.expand(sub_buckets, __CALLER__)
    cf = Macro.expand(cost_factor, __CALLER__)
    opts = Macro.expand(opts, __CALLER__)

    if Macro.quoted_literal?(buckets) && Macro.quoted_literal?(cf) do
      if !is_integer(cf), do: int_arg_error!("cost_factor")
      {:%{}, _, bucket_list} = buckets
      {buckets, t_int} = prepare_multi_params(bucket_list, cf)
      b_ast = Enum.map(buckets, fn {k, v} -> {k, Macro.escape(v)} end)
      details = get_details(opts)

      cond do
        details == true ->
          quote bind_quoted: [id: bucket_id, b_ast: b_ast, t_int: t_int, cf: cf, opts: opts] do
            AtomicBucket.__multi_request_details__(id, b_ast, t_int, cf, opts)
          end

        details == false ->
          quote bind_quoted: [id: bucket_id, b_ast: b_ast, t_int: t_int, cf: cf, opts: opts] do
            AtomicBucket.__multi_request__(id, b_ast, t_int, cf, opts)
          end

        true ->
          quote bind_quoted: [id: bucket_id, b_ast: b_ast, t_int: t_int, cf: cf, opts: opts] do
            AtomicBucket.__multi_request_check_details__(id, b_ast, t_int, cf, opts)
          end
      end
    else
      quote bind_quoted: [id: bucket_id, buckets: buckets, cf_ast: cost_factor, opts: opts] do
        AtomicBucket.__unvalidated_multi_request__(id, buckets, cf_ast, opts)
      end
    end
  end

  defp get_details(opts) when is_list(opts) do
    # Only get the value if all keys are literal atoms.
    if Enum.all?(opts, fn {k, _} -> is_atom(k) end) do
      Keyword.get(opts, :details, @detault_multi_details?)
    end
  end

  defp get_details(_opts), do: nil

  defp prepare_multi_params([], _cost_factor) do
    raise ArgumentError, "Must include at least 1 sub-bucket."
  end

  defp prepare_multi_params(buckets, cost_factor) do
    t_interval = token_interval(buckets, nil)

    prepared =
      prepare_buckets(buckets, 0, t_interval, cost_factor)
      |> Enum.sort_by(fn {_, {c, _, _}} -> c end)

    {prepared, t_interval}
  end

  defp token_interval([{_, {interval, _}} | buckets], nil) do
    if !pos_int?(interval), do: sub_bucket_arg_error!("request interval")

    token_interval(buckets, interval)
  end

  defp token_interval([{_, {interval, _}} | buckets], prev_interval) do
    if !pos_int?(interval), do: sub_bucket_arg_error!("request interval")

    token_interval(buckets, Integer.gcd(interval, prev_interval))
  end

  defp token_interval([], interval), do: interval

  defp token_interval(_, _) do
    raise ArgumentError, "Invalid sub_buckets argument."
  end

  defp prepare_buckets([], _bits_acc, _t_interval, _cf), do: []

  defp prepare_buckets([{name, {req_int, burst}} | buckets], bits_acc, t_int, cf) do
    if !pos_int?(burst), do: sub_bucket_arg_error!("burst")

    cost = div(req_int, t_int)
    scaled_cost = scaled_cost(cost, cf)
    cap = burst * cost
    bits = floor(:math.log2(cap)) + 1
    total_bits = bits_acc + bits

    if total_bits > @token_bits do
      error =
        """
        Required multi-bucket capacity (#{total_bits} bits) is above the limit (#{@token_bits}). \
        Consider increasing GCD of request intervals, reducing bursts or number of sub-buckets.
        """

      raise ArgumentError, error
    end

    [{name, {cap, bits, scaled_cost}} | prepare_buckets(buckets, total_bits, t_int, cf)]
  end

  # Zero cf is converted to 1 for calculations of remaining requests, skipped in
  # charge_all and refill_charge_all.
  defp scaled_cost(cost, 0), do: cost
  defp scaled_cost(cost, cf), do: cost * cf

  defp sub_bucket_arg_error!(name) do
    raise ArgumentError, "Invalid sub-bucket parameter: #{name} must be a positive integer."
  end

  def __unvalidated_multi_request__(id, buckets, cf, opts) do
    {buckets, t_interval} = Map.to_list(buckets) |> prepare_multi_params(cf)
    __multi_request_check_details__(id, buckets, t_interval, cf, opts)
  end

  def __multi_request_check_details__(id, buckets, t_interval, cf, opts) do
    if Keyword.get(opts, :details, @detault_multi_details?) do
      __multi_request_details__(id, buckets, t_interval, cf, opts)
    else
      __multi_request__(id, buckets, t_interval, cf, opts)
    end
  end

  def __multi_request__(id, buckets, t_interval, cf, opts) do
    {bucket_ref, atomic, prev_timer, ams_old} = get_bucket(id, buckets, opts)
    timer = get_timer(opts)
    elapsed = wrapping_timer_delta(prev_timer, timer)
    refill = div(elapsed, t_interval)

    try do
      ams_request = refill_charge_all(ams_old, buckets, refill, cf)
      timer = prev_timer + refill * t_interval
      new_atomic = pack_bucket(ams_request, timer, buckets)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, bucket_ref}

        _ ->
          __multi_request__(id, buckets, t_interval, cf, opts)
      end
    catch
      _ -> {:deny, bucket_ref}
    end
  end

  def __multi_request_details__(id, buckets, t_interval, cf, opts) do
    {bucket_ref, atomic, prev_timer, ams_old} = get_bucket(id, buckets, opts)
    timer = get_timer(opts)
    elapsed = wrapping_timer_delta(prev_timer, timer)
    refill = div(elapsed, t_interval)
    ams_refill = refill_all(ams_old, buckets, refill)
    ams_request = charge_all(ams_refill, buckets, cf)

    if Enum.all?(ams_request, &(&1 >= 0)) do
      timer = prev_timer + refill * t_interval
      new_atomic = pack_bucket(ams_request, timer, buckets)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          results = allowed_requests(ams_request, buckets, cf, %{})
          {:allow, results, bucket_ref}

        _ ->
          __multi_request_details__(id, buckets, t_interval, cf, opts)
      end
    else
      results =
        denied_requests(ams_old, ams_refill, ams_request, buckets, t_interval, elapsed, %{})

      {:deny, results, bucket_ref}
    end
  end

  defp refill_all(amounts, _, 0), do: amounts

  defp refill_all([], [], _refill), do: []

  defp refill_all([tokens | amounts], [{_, {capacity, _, _}} | buckets], refill) do
    [min(capacity, tokens + refill) | refill_all(amounts, buckets, refill)]
  end

  defp charge_all(amounts, _, 0), do: amounts

  defp charge_all([], _buckets, _cf), do: []

  defp charge_all([tokens | amounts], [{_, {_, _, cost}} | buckets], cf) do
    # Cost here already includes cost factor, applied by prepare_buckets/4.
    [tokens - cost | charge_all(amounts, buckets, cf)]
  end

  # Fast path for details=false.
  defp refill_charge_all([], [], _refill, _cf), do: []

  defp refill_charge_all(amounts, buckets, refill, 0) do
    # Zero cf = refill only.
    refill_all(amounts, buckets, refill)
  end

  defp refill_charge_all([tokens | amounts], [{_, {capacity, _, cost}} | buckets], refill, cf) do
    new_tokens = min(capacity, min(capacity, tokens + refill) - cost)

    if new_tokens >= 0 do
      [new_tokens | refill_charge_all(amounts, buckets, refill, cf)]
    else
      throw(:error)
    end
  end

  defp allowed_requests([], [], _cf, acc), do: acc

  defp allowed_requests([tokens | amounts], [{name, {_, _, cost}} | buckets], 0, acc) do
    # 0 is a special case: return value for cf = 1, prepare_buckets/4 keeps original cost.
    acc = Map.put(acc, name, div(tokens, cost))
    allowed_requests(amounts, buckets, 0, acc)
  end

  defp allowed_requests([tokens | amounts], [{name, {_, _, cost}} | buckets], cf, acc) do
    acc = Map.put(acc, name, div(tokens, abs(cost)))
    allowed_requests(amounts, buckets, cf, acc)
  end

  defp denied_requests([], [], [], [], _t_interval, _elapsed, acc), do: acc

  defp denied_requests(
         [t_old | ams_old],
         [t_refill | ams_refill],
         [t_request | ams_request],
         [{name, {_, _, cost}} | buckets],
         t_interval,
         elapsed,
         acc
       ) do
    # Cost here already includes cost factor, applied by prepare_buckets/4.
    # The cost is positive, because zero and negative cf can't result in denied req.
    result =
      if t_request >= 0 do
        # Positive verdict here doesn't mean we subtract the amount.
        {:allow, div(t_refill, cost)}
      else
        {:deny, (cost - t_old) * t_interval - elapsed}
      end

    acc = Map.put(acc, name, result)

    denied_requests(ams_old, ams_refill, ams_request, buckets, t_interval, elapsed, acc)
  end

  defp expand_int(ast, name, env, pos? \\ false) do
    case Macro.expand(ast, env) do
      i when is_integer(i) ->
        {:ok, i}

      {:-, _, [i]} when is_integer(i) ->
        if pos?, do: pos_int_arg_error!(name), else: {:ok, i}

      other ->
        if Macro.quoted_literal?(other) do
          if pos?, do: pos_int_arg_error!(name), else: int_arg_error!(name)
        else
          :error
        end
    end
  end

  defp pos_int?(value), do: is_integer(value) && value > 0

  defp int_arg_error!(name) do
    raise ArgumentError, "Invalid argument: #{name} must be an integer."
  end

  defp pos_int_arg_error!(name) do
    raise ArgumentError, "Invalid argument: #{name} must be a positive integer."
  end

  defp get_bucket(bucket_id, capacity_info, opts) do
    cond do
      bucket_ref = Keyword.get(opts, :ref) ->
        open_bucket(bucket_ref, bucket_id, capacity_info, opts)

      bucket_ref = persistent_bucket?(opts) && pt_get(bucket_id, opts) ->
        open_bucket(bucket_ref, bucket_id, capacity_info, opts)

      true ->
        case :ets.lookup(table(opts), bucket_id) do
          [{_, bucket_ref}] ->
            open_bucket(bucket_ref, bucket_id, capacity_info, opts)

          [] ->
            try_create_bucket(bucket_id, capacity_info, opts)
        end
    end
  end

  defp open_bucket(bucket_ref, bucket_id, capacity_info, opts) do
    atomic = :atomics.get(bucket_ref, 1)

    case unpack_bucket(atomic, capacity_info) do
      {tokens, timer, 0} ->
        {bucket_ref, atomic, timer, tokens}

      _ ->
        # When deleting buckets, after updating the atomic the server will
        # delete references to it, and eventually some process (or the
        # current one) will succeed in recreating it, if we keep retrying.
        # We make sure this is not a reference passed via options, so that
        # we don't get stuck in infinite loop.
        opts = Keyword.drop(opts, [:ref])
        get_bucket(bucket_id, capacity_info, opts)
    end
  end

  defp try_create_bucket(bucket, capacity_info, opts) do
    table = table(opts)
    bucket_ref = :atomics.new(1, signed: false)
    timer = get_timer(opts)
    tokens = new_bucket_tokens(capacity_info)
    atomic = pack_bucket(tokens, timer, capacity_info)
    :atomics.put(bucket_ref, 1, atomic)

    if :ets.insert_new(table, {bucket, bucket_ref}) do
      if persistent_bucket?(opts) do
        :persistent_term.put(pt_bucket_key(table, bucket), bucket_ref)
      end

      {bucket_ref, atomic, timer, tokens}
    else
      get_bucket(bucket, capacity_info, opts)
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

  if @test_env? do
    defp get_timer(opts) do
      Keyword.get(opts, :timer) || wrapping_timer()
    end
  else
    defp get_timer(_opts) do
      wrapping_timer()
    end
  end

  defp wrapping_timer() do
    rem = rem(System.monotonic_time(:millisecond), @timer_modulus)
    if rem < 0, do: rem + @timer_modulus, else: rem
  end

  defp wrapping_timer_delta(timer1, timer2) do
    delta = timer2 - timer1
    if delta >= 0, do: delta, else: delta + @timer_modulus
  end

  defp new_bucket_tokens(capacity) when is_integer(capacity) do
    capacity
  end

  defp new_bucket_tokens(buckets) do
    Enum.map(buckets, fn {_, {c, _, _}} -> c end)
  end

  defp pack_bucket(tokens, timer, _capacity) when is_integer(tokens) do
    tokens <<< (@timer_bits + 1) ||| timer <<< 1
  end

  defp pack_bucket(checked_amounts, timer, buckets) do
    pack_tokens(checked_amounts, buckets, timer <<< 1, @timer_bits + 1)
  end

  defp pack_tokens([], [], value, _shift), do: value

  defp pack_tokens([tokens | amounts], [{_, {_, bits, _}} | buckets], value, shift) do
    pack_tokens(amounts, buckets, tokens <<< shift ||| value, shift + bits)
  end

  defp unpack_bucket(atomic, capacity) when is_integer(capacity) do
    tokens = atomic >>> (@timer_bits + 1)
    timer = bucket_timer(atomic)
    deleted = atomic &&& 1
    {tokens, timer, deleted}
  end

  defp unpack_bucket(atomic, buckets) do
    deleted = atomic &&& 1
    tokens_timer = atomic >>> 1
    timer = tokens_timer &&& (1 <<< @timer_bits) - 1
    amounts = unpack_tokens(tokens_timer, buckets, [], @timer_bits)

    {amounts, timer, deleted}
  end

  defp unpack_tokens(_atomic, [], amounts, _shift), do: amounts

  defp unpack_tokens(atomic, [{_, {_, bits, _}} | buckets], amounts, shift) do
    shifted = atomic >>> shift
    value = shifted &&& (1 <<< bits) - 1
    [value | unpack_tokens(shifted, buckets, amounts, bits)]
  end

  defp bucket_timer(atomic) do
    atomic >>> 1 &&& (1 <<< @timer_bits) - 1
  end

  def child_spec(init_arg) do
    %{
      id: {__MODULE__, Keyword.get(init_arg, :table, __MODULE__)},
      start: {__MODULE__, :start_link, [init_arg]}
    }
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
      to delete idle buckets. It is applied on completion of a cleanup.
      Default is 1 hour.

    - `:max_idle_period` max period in ms since last bucket update before
      it is deleted. Default is 24 hours.

    - `:table` ETS table name atom. Default is AtomicBucket.
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

    state = %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period}
    {:ok, state, :hibernate}
  end

  defp cleanup_interval(opts), do: Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)

  defp max_idle_period(opts), do: Keyword.get(opts, :max_idle_period, @default_max_idle_period)

  @impl true
  def handle_info(:cleanup, state) do
    %{table: table, cleanup_interval: cleanup_interval, max_idle_period: max_idle_period} = state

    # Make sure only 1 task can run at a time.
    Task.async(fn ->
      fn {bucket, bucket_ref}, _ ->
        atomic = :atomics.get(bucket_ref, 1)
        timer = wrapping_timer()
        bucket_timer = bucket_timer(atomic)
        pending? = wrapping_timer_delta(bucket_timer, timer) > max_idle_period

        if pending? && :ok == :atomics.compare_exchange(bucket_ref, 1, atomic, 1) do
          :ets.delete_object(table, {bucket, bucket_ref})
          :persistent_term.erase(pt_bucket_key(table, bucket))
        end
      end
      |> :ets.foldl(nil, table)
    end)
    |> Task.await(:infinity)

    schedule_cleanup(cleanup_interval)

    {:noreply, state, :hibernate}
  end

  def handle_info(_, state), do: {:noreply, state, :hibernate}

  defp schedule_cleanup(cleanup_interval) do
    Process.send_after(self(), :cleanup, cleanup_interval)
  end

  def __max_capacity__(), do: @max_capacity
end
