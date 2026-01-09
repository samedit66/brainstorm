defmodule Brainfuck.CompileTimeExecutor do
  @moduledoc """
  Executes a prefix of Brainfuck commands at compile time.
  """

  @doc """
  Execute Brainfuck commands at compile time.

  Execution proceeds until one of the following happens:
  - the program finishes -> `{:full, env, []}`
  - an `:in` command is encountered -> `{:partial, env, remaining_commands}`
  - a loop (`{:loop, _}`) is encountered -> `{:partial, env, remaining_commands}`

  ## Examples

      iex> Brainfuck.CompileTimeExecutor.execute([:out])
      {:full, %{i: 0, tape: %{}, out_queue: [0]}}

      iex> Brainfuck.CompileTimeExecutor.execute([:in])
      {:partial, %{i: 0, tape: %{}, out_queue: []}, [:in]}

      iex> Brainfuck.CompileTimeExecutor.execute([{:loop, []}])
      {:partial, %{i: 0, tape: %{}, out_queue: []}, [{:loop, []}]}

      iex> Brainfuck.CompileTimeExecutor.execute([
      ...>   {:inc, 2, 0},
      ...>   {:mult, 3, 1},
      ...>   {:shift, 1},
      ...>   :out
      ...> ])
      {:full, %{i: 1, tape: %{0 => 2, 1 => 6}, out_queue: [6]}}

  """
  def execute(commands) do
    do_execute(commands, %{i: 0, tape: %{}, out_queue: []})
    |> prepare_output()
  end

  defp do_execute([], env), do: {:full, env}

  defp do_execute([:zero | rest], %{i: i, tape: tape} = env) do
    do_execute(rest, %{env | tape: Map.put(tape, i, 0)})
  end

  defp do_execute([{:inc, by, offset} | rest], %{i: i, tape: tape} = env) do
    key = i + offset
    dest_value = Map.get(tape, key, 0)
    tape = Map.put(tape, key, dest_value + by)
    do_execute(rest, %{env | tape: tape})
  end

  defp do_execute([{:mult, by, offset} | rest], %{i: i, tape: tape} = env) do
    current_value = Map.get(tape, i, 0)
    key = i + offset
    dest_value = Map.get(tape, key, 0)
    tape = Map.put(tape, key, dest_value + current_value * by)
    do_execute(rest, %{env | tape: tape})
  end

  defp do_execute([{:shift, offset} | rest], %{i: i} = env) do
    do_execute(rest, %{env | i: i + offset})
  end

  defp do_execute([:out | rest], %{i: i, tape: tape, out_queue: out_queue} = env) do
    value = Map.get(tape, i, 0)
    do_execute(rest, %{env | out_queue: [value | out_queue]})
  end

  defp do_execute([:in | _rest] = commands, env) do
    {:partial, env, commands}
  end

  defp do_execute([{:loop, body} | rest] = commands, %{i: i, tape: tape} = env) do
    case Map.get(tape, i, 0) do
      0 -> do_execute(rest, env)

      _non_zero ->
        case do_execute(body, env) do
          {:partial, _env_after, _remaning} ->
            {:partial, env, commands}

          {:full, env_after} ->
            do_execute(commands, env_after)
        end
    end
  end

  defp prepare_output({:full, %{out_queue: out_queue} = env}) do
    {:full, %{env | out_queue: Enum.reverse(out_queue)}}
  end

  defp prepare_output({:partial, %{out_queue: out_queue} = env, remaining}) do
    {:partial, %{env | out_queue: Enum.reverse(out_queue)}, remaining}
  end
end
