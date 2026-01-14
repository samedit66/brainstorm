defmodule Brainstorm.CompileTimeExecutor do
  @moduledoc """
  Executes some of Brainfuck commands at compile time.
  """

  @doc """
  Execute some of Brainfuck commands at compile time.

  Execution proceeds until one of the following happens:
  - the program finishes -> `{:full, state}`
  - an `:in` command is encountered -> `{:partial, state, remaining_commands}`
  - a loop that cannot be fully executed at compile time -> `{:partial, state, remaining_commands}`

  The returned `state` contains `:i` (current tape position),
  `:tape` (map which keys are indexes at tape and values are... values, yeah)
  and `:out_queue` (characters to print on screen).

  ## Examples

      iex> Brainstorm.CompileTimeExecutor.execute([:out])
      {:full, %{i: 0, tape: %{}, out_queue: [0]}}

      iex> Brainstorm.CompileTimeExecutor.execute([:in])
      {:partial, %{i: 0, tape: %{}, out_queue: []}, [:in]}

      iex> Brainstorm.CompileTimeExecutor.execute([{:loop, []}])
      {:full, %{i: 0, tape: %{}, out_queue: []}}

      iex> Brainstorm.CompileTimeExecutor.execute([
      ...>   {:inc, 2, 0},
      ...>   {:mult, 3, 1},
      ...>   {:shift, 1},
      ...>   :out
      ...> ])
      {:full, %{i: 1, tape: %{0 => 2, 1 => 6}, out_queue: [6]}}

      iex> Brainstorm.CompileTimeExecutor.execute([{:set, 3}, {:loop, [:out, {:inc, -1, 0}]}])
      {:full, %{i: 0, tape: %{0 => 0}, out_queue: [3, 2, 1]}}

      iex> Brainstorm.CompileTimeExecutor.execute([{:set, 1300}, {:loop, [{:inc, -1, 0}]}])
      {:partial, %{i: 0, tape: %{0 => 276}, out_queue: []}, [{:loop, [{:inc, -1, 0}]}]}

  """
  def execute(commands, opts \\ []) do
    max_loop_steps = Keyword.get(opts, :max_loop_steps, 1024)

    state = %{
      i: 0,
      tape: %{},
      out_queue: [],
      max_loop_steps: max_loop_steps,
      loop_steps: 0
    }

    do_execute(commands, state) |> prepare_output()
  end

  defp do_execute([], state), do: {:full, state}

  defp do_execute([{:scan, n} | rest] = commands, %{i: i, tape: tape} = state) do
    dest_key = i + n

    if Map.get(tape, dest_key, 0) do
      do_execute(rest, %{state | i: dest_key})
    else
      do_execute(commands, %{state | i: dest_key})
    end
  end

  defp do_execute([{:set, value} | rest], %{i: i, tape: tape} = state) do
    do_execute(rest, %{state | tape: Map.put(tape, i, value)})
  end

  defp do_execute([{:inc, by, offset} | rest], %{i: i, tape: tape} = state) do
    key = i + offset
    dest_value = Map.get(tape, key, 0)
    tape = Map.put(tape, key, dest_value + by)
    do_execute(rest, %{state | tape: tape})
  end

  defp do_execute([{:mult, by, offset} | rest], %{i: i, tape: tape} = state) do
    current_value = Map.get(tape, i, 0)
    key = i + offset
    dest_value = Map.get(tape, key, 0)
    tape = Map.put(tape, key, dest_value + current_value * by)
    do_execute(rest, %{state | tape: tape})
  end

  defp do_execute([{:div, by, offset} | rest], %{i: i, tape: tape} = state) do
    current_value = Map.get(tape, i, 0)
    key = i + offset
    dest_value = Map.get(tape, key, 0)
    tape = Map.put(tape, key, dest_value + current_value / by)
    do_execute(rest, %{state | tape: tape})
  end

  defp do_execute([{:shift, offset} | rest], %{i: i} = state) do
    do_execute(rest, %{state | i: i + offset})
  end

  defp do_execute([:out | rest], %{i: i, tape: tape, out_queue: out_queue} = state) do
    value = Map.get(tape, i, 0)
    do_execute(rest, %{state | out_queue: [value | out_queue]})
  end

  defp do_execute([:in | _rest] = commands, state) do
    {:partial, state, commands}
  end

  defp do_execute(
         [{:loop, _body} | _rest] = commands,
         %{loop_steps: l, max_loop_steps: ml} = state
       )
       when l == ml do
    {:partial, state, commands}
  end

  defp do_execute(
         [{:loop, body} | rest] = commands,
         %{i: i, tape: tape, loop_steps: loop_steps} = state
       ) do
    case Map.get(tape, i, 0) do
      0 ->
        do_execute(rest, %{state | loop_steps: 0})

      _non_zero ->
        case do_execute(body, state) do
          {:partial, _state_after, _remaining} ->
            {:partial, %{state | loop_steps: 0}, commands}

          {:full, state_after} ->
            do_execute(commands, %{state_after | loop_steps: loop_steps + 1})
        end
    end
  end

  defp prepare_output({:full, %{i: i, tape: tape, out_queue: out_queue}}) do
    result_state = %{i: i, tape: tape, out_queue: Enum.reverse(out_queue)}
    {:full, result_state}
  end

  defp prepare_output({:partial, %{i: i, tape: tape, out_queue: out_queue}, remaining}) do
    result_state = %{i: i, tape: tape, out_queue: Enum.reverse(out_queue)}
    {:partial, result_state, remaining}
  end
end
