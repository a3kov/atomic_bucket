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
  @test_env? Application.compile_env(:atomic_bucket, :test_env, false)
  @compile {:inline,
            [
              validate_raw_params!: 3,
              validate_rates!: 1,
              get_bucket: 5,
              open_bucket: 6,
              try_create_bucket: 5,
              pack_bucket: 3,
              unpack_bucket: 2,
              bucket_timer: 1,
              wrapping_timer: 0,
              get_timer: 1,
              wrapping_timer_delta: 2,
              pos_int?: 1,
              pt_key: 2
            ]}

  @type verdict :: :allow | :deny

  def _unvalidated_req(bucket, table, window, requests, burst, persistent, idle_p, opts) do
    {capacity, refill_ms, cost} = fixed_cost_params(window, requests, burst, idle_p)
    _validated_req(bucket, table, capacity, refill_ms, cost, persistent, opts)
  end

  def _validated_req(bucket, table, capacity, refill_ms, cost, persistent, opts) do
    timer = get_timer(opts)

    {bucket_ref, atomic, prev_timer, tokens} =
      get_bucket(bucket, table, capacity, persistent, opts)

    tokens_after_refill =
      min(capacity, tokens + refill_ms * wrapping_timer_delta(prev_timer, timer))

    tokens_after_request = tokens_after_refill - cost

    if tokens_after_request >= 0 do
      new_atomic = pack_bucket(tokens_after_request, timer, capacity)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, div(tokens_after_request, cost), bucket_ref}

        _ ->
          _validated_req(bucket, table, capacity, refill_ms, cost, persistent, opts)
      end
    else
      {:deny, div(cost - tokens_after_refill, refill_ms), bucket_ref}
    end
  end

  @doc false
  def fixed_cost_params(window, requests, burst_requests, idle_period) do
    if !pos_int?(window), do: pos_int_arg_error!("window")
    if !pos_int?(requests), do: pos_int_arg_error!("window_requests")
    if !pos_int?(burst_requests), do: pos_int_arg_error!("burst_requests")

    window_ms = window * 1000

    if window_ms >= idle_period do
      raise ArgumentError, "Window must be less than max_idle_period (#{idle_period} ms)."
    end

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

  def _unvalidated_raw_req(id, table, capacity, refill_ms, cost, persistent, opts) do
    validate_raw_params!(capacity, refill_ms, cost)
    _validated_raw_req(id, table, capacity, refill_ms, cost, persistent, opts)
  end

  def _validated_raw_req(id, table, capacity, refill_ms, cost, persistent, opts) do
    timer = get_timer(opts)
    {bucket_ref, atomic, prev_timer, tokens} = get_bucket(id, table, capacity, persistent, opts)
    elapsed = wrapping_timer_delta(prev_timer, timer)
    tokens_after_refill = min(capacity, tokens + refill_ms * elapsed)
    tokens_after_request = min(capacity, tokens_after_refill - cost)

    if tokens_after_request >= 0 do
      new_atomic = pack_bucket(tokens_after_request, timer, capacity)

      case :atomics.compare_exchange(bucket_ref, 1, atomic, new_atomic) do
        :ok ->
          {:allow, tokens_after_request, bucket_ref}

        _ ->
          _validated_raw_req(id, table, capacity, refill_ms, cost, persistent, opts)
      end
    else
      {:deny, tokens_after_refill, bucket_ref}
    end
  end

  @doc false
  def validate_raw_params!(capacity, refill_ms, cost) do
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

  @doc false
  def multi_params([], _cost_factor) do
    raise ArgumentError, "Must include at least 1 sub-bucket."
  end

  def multi_params(buckets, cost_factor) do
    # token_interval/1 must be first because it's doing validation.
    t_interval = token_interval(buckets)
    sorted_buckets = Enum.sort_by(buckets, fn {_, {i, _}} -> i end)
    validate_rates!(sorted_buckets)
    prepared = prepare_buckets(sorted_buckets, 0, t_interval, cost_factor)

    {prepared, t_interval}
  end

  defp validate_rates!([{_, {interval, burst}} | buckets]) do
    validate_rates!(buckets, interval, burst)
  end

  defp validate_rates!([], _, _), do: :ok

  defp validate_rates!([{_, {interval, _}} | _], interval, _) do
    raise ArgumentError, "Sub-bucket rates must be different."
  end

  defp validate_rates!([{_, {interval, burst}} | buckets], _, prev_burst) do
    if burst <= prev_burst do
      raise ArgumentError, "Sub-buckets with lower rates must have bigger bursts."
    else
      validate_rates!(buckets, interval, burst)
    end
  end

  defp token_interval([{_, {interval, _}} | buckets]) do
    if !pos_int?(interval), do: sub_bucket_arg_error!("request interval")

    token_interval(buckets, interval)
  end

  defp token_interval(_) do
    raise ArgumentError, "Invalid sub_buckets argument."
  end

  defp token_interval([{_, {interval, _}} | buckets], prev_interval) do
    if !pos_int?(interval), do: sub_bucket_arg_error!("request interval")

    token_interval(buckets, Integer.gcd(interval, prev_interval))
  end

  defp token_interval([], interval), do: interval

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

  def _unvalidated_multi_req(id, table, buckets, cf, persistent, opts) do
    {buckets, t_interval} = Map.to_list(buckets) |> multi_params(cf)
    _multi_req(id, table, buckets, t_interval, cf, persistent, opts)
  end

  def _unvalidated_multi_req_details(id, table, buckets, cf, persistent, opts) do
    {buckets, t_interval} = Map.to_list(buckets) |> multi_params(cf)
    _multi_req_details(id, table, buckets, t_interval, cf, persistent, opts)
  end

  def _multi_req(id, table, buckets, t_interval, cf, persistent, opts) do
    {bucket_ref, atomic, prev_timer, ams_old} =
      get_bucket(id, table, buckets, persistent, opts)

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
          _multi_req(id, table, buckets, t_interval, cf, persistent, opts)
      end
    catch
      _ -> {:deny, bucket_ref}
    end
  end

  def _multi_req_details(id, table, buckets, t_interval, cf, persistent, opts) do
    {bucket_ref, atomic, prev_timer, ams_old} =
      get_bucket(id, table, buckets, persistent, opts)

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
          _multi_req_details(id, table, buckets, t_interval, cf, persistent, opts)
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

  # Fast path skipping details.
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
      throw(:deny)
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

  @doc false
  def validated_rate_limiter_opts(opts, module) do
    if !Keyword.keyword?(opts) do
      raise ArgumentError, "Rate limiter options must be a keyword list"
    end

    table = Keyword.get(opts, :table, module)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    max_idle_period = Keyword.get(opts, :max_idle_period, @default_max_idle_period)
    persistent = Keyword.get(opts, :persistent, false)

    if !is_atom(table) do
      raise ArgumentError, "Rate limiter table must be an atom"
    end

    validate_cleanup_arg!(cleanup_interval, :cleanup_interval)
    validate_cleanup_arg!(max_idle_period, :max_idle_period)

    if cleanup_interval > max_idle_period do
      raise ArgumentError, "cleanup_interval must be less than or equal to max_idle_period"
    end

    if !is_boolean(persistent) do
      raise ArgumentError, "persistent must be a boolean"
    end

    %{
      table: table,
      cleanup_interval: cleanup_interval,
      max_idle_period: max_idle_period,
      persistent: persistent
    }
  end

  defp validate_cleanup_arg!(value, name) do
    max_window_ms = @max_window * 1000

    if !is_integer(value) || value <= 0 || value >= max_window_ms do
      raise ArgumentError, "#{name} must be a positive integer less than #{max_window_ms}"
    end
  end

  @doc false
  def set_rate_limiter_attributes(validated_opts, module) do
    %{
      table: table,
      cleanup_interval: cleanup_interval,
      max_idle_period: max_idle_period,
      persistent: persistent
    } = validated_opts

    Module.put_attribute(module, :atomic_bucket_table, table)
    Module.put_attribute(module, :atomic_bucket_cleanup_interval, cleanup_interval)
    Module.put_attribute(module, :atomic_bucket_max_idle_period, max_idle_period)
    Module.put_attribute(module, :atomic_bucket_persistent, persistent)
  end

  @doc false
  def expand_int(ast, name, env, pos? \\ false) do
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

  @doc false
  def int_arg_error!(name) do
    raise ArgumentError, "Invalid argument: #{name} must be an integer."
  end

  defp pos_int_arg_error!(name) do
    raise ArgumentError, "Invalid argument: #{name} must be a positive integer."
  end

  defp get_bucket(id, table, capacity_info, persistent, opts) do
    cond do
      ref = Keyword.get(opts, :ref) ->
        open_bucket(ref, id, table, capacity_info, persistent, opts)

      ref = persistent && :persistent_term.get(pt_key(table, id), nil) ->
        open_bucket(ref, id, table, capacity_info, persistent, opts)

      true ->
        case :ets.lookup(table, id) do
          [{_, ref}] ->
            open_bucket(ref, id, table, capacity_info, persistent, opts)

          [] ->
            try_create_bucket(id, table, capacity_info, persistent, opts)
        end
    end
  end

  defp open_bucket(ref, id, table, capacity_info, persistent, opts) do
    atomic = :atomics.get(ref, 1)

    case unpack_bucket(atomic, capacity_info) do
      {tokens, timer, 0} ->
        {ref, atomic, timer, tokens}

      _ ->
        # When deleting buckets, after updating the atomic the server will
        # delete references to it, and eventually some process (or the
        # current one) will succeed in recreating it, if we keep retrying.
        # We make sure this is not a reference passed via options, so that
        # we don't get stuck in infinite loop.
        opts = Keyword.drop(opts, [:ref])
        get_bucket(id, table, capacity_info, persistent, opts)
    end
  end

  defp try_create_bucket(id, table, capacity_info, persistent, opts) do
    bucket_ref = :atomics.new(1, signed: false)
    timer = get_timer(opts)
    tokens = new_bucket_tokens(capacity_info)
    atomic = pack_bucket(tokens, timer, capacity_info)
    :atomics.put(bucket_ref, 1, atomic)

    if :ets.insert_new(table, {id, bucket_ref}) do
      if persistent do
        :persistent_term.put(pt_key(table, id), bucket_ref)
      end

      {bucket_ref, atomic, timer, tokens}
    else
      get_bucket(id, table, capacity_info, persistent, opts)
    end
  end

  defp pt_key(table, id), do: {__MODULE__, table, id}

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

  @doc false
  def child_spec(_init_arg) do
    raise ArgumentError, "Use a rate limiter module to start the server."
  end

  @doc false
  def start_link(opts) do
    gen_keys = [:debug, :name, :timeout, :spawn_opt]
    {gen_opts, opts} = Keyword.split(opts, gen_keys)
    init_arg = Map.new(opts)
    GenServer.start_link(__MODULE__, init_arg, gen_opts)
  end

  @impl true
  def init(params) do
    %{type: module, table: table, cleanup_interval: cleanup_interval} = params

    Process.set_label({__MODULE__, module, table})

    :ets.new(table, [
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    schedule_cleanup(cleanup_interval)

    {:ok, params, :hibernate}
  end

  @impl true
  def handle_info(:cleanup, state) do
    %{
      table: table,
      cleanup_interval: cleanup_interval,
      max_idle_period: max_idle_period,
      persistent: persistent
    } = state

    # Make sure only 1 task can run at a time.
    Task.async(fn ->
      fn {id, bucket_ref}, _ ->
        atomic = :atomics.get(bucket_ref, 1)
        timer = wrapping_timer()
        bucket_timer = bucket_timer(atomic)
        pending? = wrapping_timer_delta(bucket_timer, timer) > max_idle_period

        if pending? && :ok == :atomics.compare_exchange(bucket_ref, 1, atomic, 1) do
          :ets.delete_object(table, {id, bucket_ref})
          persistent && :persistent_term.erase(pt_key(table, id))
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

  def _max_capacity(), do: @max_capacity
end
