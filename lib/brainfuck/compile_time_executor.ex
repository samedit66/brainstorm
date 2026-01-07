defmodule Brainfuck.CompileTimeExecutor do
  @moduledoc """
  Executes a prefix of Brainfuck commands at compile time.
  """

  @doc """
  Execute Brainfuck commands at compile time.

  Execution proceeds until one of the following happens:
  - the program finishes -> `{:full, env}`
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
  end

  defp do_execute([], env), do: {:full, prepare_output(env)}

  defp do_execute([:zero | rest], %{i: i, tape: tape} = env) do
    do_execute(rest, %{env | tape: Map.put(tape, i, 0)})
  end

  defp do_execute([{:inc, by, offset} | rest], %{i: i, tape: tape} = env) do
    key = i + offset
    value = Map.get(tape, key, 0)
    do_execute(rest, %{env | tape: Map.put(tape, key, value + by)})
  end

  defp do_execute([{:mult, by, offset} | rest], %{i: i, tape: tape} = env) do
    src = Map.get(tape, i, 0)
    dest_key = i + offset
    dest = Map.get(tape, dest_key, 0)
    tape = Map.put(tape, dest_key, dest + src * by)
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
    {:partial, prepare_output(env), commands}
  end

  defp do_execute([{:loop, _body} | _rest] = commands, env) do
    {:partial, prepare_output(env), commands}
  end

  defp prepare_output(%{out_queue: out_queue} = env) do
    %{env | out_queue: Enum.reverse(out_queue)}
  end
end
