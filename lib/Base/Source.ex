defmodule Base.Source do
  alias Membrane.Buffer
  alias Membrane.Time

  @message :crypto.strong_rand_bytes(1000)
  @interval 10

  def handle_init(opts) do
    messages_per_second = ((opts.initial_lower_bound + opts.initial_upper_bound) / 2) |> trunc()
    messages_per_interval = (messages_per_second * @interval / 1000) |> trunc()

    {:ok,
     %{
       messages_per_interval: messages_per_interval,
       status: :playing,
       messages_per_second: messages_per_second,
       lower_bound: opts.initial_lower_bound,
       upper_bound: opts.initial_upper_bound
     }}
  end

  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, start_timer: {:next_buffer_timer, Ratio.new(Time.milliseconds(@interval), 1)}}, state}
  end

  def handle_tick(:next_buffer_timer, _ctx, state = %{status: :playing}) do
    buffers =
      for _i <- 1..state.messages_per_interval,
          do: %Buffer{payload: @message, dts: Membrane.Time.monotonic_time()}

    actions = [buffer: {:output, buffers}]
    {{:ok, actions}, state}
  end

  def handle_other(:flush, _ctx, state = %{status: :playing}) do
    actions = [
      buffer: {:output, %Buffer{payload: :flush, metadata: state.messages_per_second}},
      stop_timer: :next_buffer_timer
    ]

    state = %{state | status: :flushing}
    {{:ok, actions}, state}
  end

  def handle_other({:play, :slower}, _ctx, state = %{status: :flushing}) do
    state = %{state | status: :playing, upper_bound: state.messages_per_second}
    messages_per_second = ((state.lower_bound + state.upper_bound) / 2) |> trunc()
    messages_per_interval = (messages_per_second * @interval / 1000) |> trunc()

    state = %{
      state
      | messages_per_interval: messages_per_interval,
        messages_per_second: messages_per_second
    }

    {{:ok, start_timer: {:next_buffer_timer, Ratio.new(Time.milliseconds(@interval), 1)}}, state}
  end

  def handle_other({:play, :the_same}, _ctx, state = %{status: :flushing}) do
    state = %{state | status: :playing}
    {{:ok, start_timer: {:next_buffer_timer, Ratio.new(Time.milliseconds(@interval), 1)}}, state}
  end

  def handle_other({:play, :faster}, _ctx, state = %{status: :flushing}) do
    state = %{state | status: :playing, lower_bound: state.messages_per_second}
    messages_per_second = ((state.lower_bound + state.upper_bound) / 2) |> trunc()
    messages_per_interval = (messages_per_second * @interval / 1000) |> trunc()

    state = %{
      state
      | messages_per_interval: messages_per_interval,
        messages_per_second: messages_per_second
    }

    {{:ok, start_timer: {:next_buffer_timer, Ratio.new(Time.milliseconds(@interval), 1)}}, state}
  end

  def handle_other(_msg, _ctx, state) do
    {:ok, state}
  end
end