defmodule Brainstorm.Executor do
  @doc """
  Executes given Brainfuck code.

  Based on the provided execution `mode`, performs one of the following:

  - `:int` - **Interpreter mode**: Acts as a standard Brainfuck interpreter,
    executing each command including I/O operations.
  - `:comp` - **Compile mode**: Executes the code as much as possible, stopping
    when an `:in` command (input) is encountered. When an `:out` command is encountered,
    pushes the output byte to "virtual out-queue" which contains bytes to print.
    Returns (potentially) simplified commands that can be used to generate a complete program,
    such as a compile-time `"Hello World"` program.

  Return values:

  - `:ok` - Interpreter mode finished suc cessfully.
  - `{:compiled, commands}` - Compile mode produced a compiled command list.
  - `{:error, reason}` - An error occurred (for example `{:error, :hit_step_limit}` when the `:max_steps` limit was reached).

  """
  def run(commands, mode, max_steps) do
    initial_state = %{
      i: 0,
      tape: %{},
      steps: 0,
      max_steps: max_steps,
      out_queue: [],
      mode: mode
    }

    run_sequence(commands, initial_state) |> post_process()
  end

  defp run_sequence(
         _commands,
         %{steps: steps, max_steps: max_steps, mode: :int}
       )
       when max_steps != :infinity and steps >= max_steps do
    {:error, :hit_step_limit}
  end

  defp run_sequence(
         commands,
         %{steps: steps, max_steps: max_steps, mode: :comp} = state
       )
       when max_steps != :infinity and steps >= max_steps do
    {:stop, state, commands}
  end

  defp run_sequence([], state), do: {:end, state}

  defp run_sequence([first | rest] = commands, %{steps: steps} = state) do
    case run_single(first, %{state | steps: steps + 1}) do
      {:next, state_after} ->
        run_sequence(rest, state_after)

      {:repeat, state_after} ->
        run_sequence(commands, state_after)

      {:stop, _state_after} ->
        {:stop, state, commands}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # loop: either skip body or execute body; on body incomplete -> preserve outer state and return incomplete
  defp run_single({:loop, body}, %{i: i, tape: tape} = state) do
    if Map.get(tape, i, 0) == 0 do
      {:next, state}
    else
      case run_sequence(body, state) do
        {:end, state_after} ->
          {:repeat, state_after}

        {:stop, _state_after, _commands} ->
          {:stop, state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp run_single({:shift, offset}, %{i: i} = state) do
    {:next, %{state | i: i + offset}}
  end

  defp run_single({:scan, offset}, %{i: i, tape: tape} = state) do
    case Map.get(tape, i, 0) do
      0 -> {:next, state}
      _non_zero -> {:repeat, %{state | i: i + offset}}
    end
  end

  defp run_single({:set, value}, %{i: i, tape: tape} = state) do
    {:next, %{state | tape: Map.put(tape, i, clamp_integer(value))}}
  end

  defp run_single({:inc, by, offset}, %{i: i, tape: tape} = state) do
    new_tape = do_arithmetic(:inc, by, offset, tape, i)
    {:next, %{state | tape: new_tape}}
  end

  defp run_single({:mult, by, offset}, %{i: i, tape: tape} = state) do
    new_tape = do_arithmetic(:mult, by, offset, tape, i)
    {:next, %{state | tape: new_tape}}
  end

  defp run_single({:div, by, offset}, %{i: i, tape: tape} = state) do
    new_tape = do_arithmetic(:div, by, offset, tape, i)
    {:next, %{state | tape: new_tape}}
  end

  defp run_single(
         {:out, offset},
         %{i: i, tape: tape, out_queue: out_queue, mode: :comp} = state
       ) do
    dest_value = Map.get(tape, i + offset, 0)
    {:next, %{state | out_queue: [dest_value | out_queue]}}
  end

  defp run_single(
         {:out, offset},
         %{i: i, tape: tape, mode: :int} = state
       ) do
    value = Map.get(tape, i + offset, 0)
    IO.write(<<value>>)
    {:next, state}
  end

  defp run_single({:in, _offset}, %{mode: :comp} = state), do: {:stop, state}

  # input in interpreter mode: read 1 byte (IO.getn/2) and store its codepoint (0 if none)
  defp run_single({:in, offset}, %{i: i, tape: tape} = state) do
    # read exactly 1 character (may be an empty string if EOF)
    char =
      case IO.getn("", 1) do
        :eof -> 0
        data -> data
      end

    value =
      case String.to_charlist(char) do
        [codepoint | _] -> codepoint
        [] -> 0
      end

    dest = i + offset
    new_state = %{state | tape: Map.put(tape, dest, clamp_integer(value))}
    {:next, new_state}
  end

  defp do_arithmetic(op, arg, offset, tape, i) do
    dest = i + offset
    dest_value = Map.get(tape, dest, 0)
    current_value = Map.get(tape, i, 0)

    result =
      case op do
        :inc -> dest_value + arg
        :mult -> dest_value + current_value * arg
        :div -> dest_value - current_value * arg
      end

    Map.put(tape, dest, clamp_integer(result))
  end

  defp clamp_integer(n), do: rem(n, 256)

  defp post_process({:end, %{mode: :int}}), do: :ok

  # Tiny optimization: no need to generate `:init_temp`, when
  # the whole program got executed at compile-time
  defp post_process({:end, %{mode: :comp, out_queue: out_queue}}) do
    {:compiled, build_out_chars(out_queue)}
  end

  defp post_process({:stop, %{mode: :comp} = state, remaining_commands}) do
    {:compiled, initial_commands(state) ++ remaining_commands}
  end

  defp post_process({:error, reason}), do: {:error, reason}

  def initial_commands(%{i: i, tape: tape, out_queue: out_queue}) do
    build_init_shift(i) ++ build_init_tape(tape) ++ build_out_chars(out_queue)
  end

  defp build_init_shift(0), do: []
  defp build_init_shift(i), do: [{:shift, i}]

  defp build_init_tape(tape) when map_size(tape) > 0, do: [{:init_tape, tape}]
  defp build_init_tape(_empty_tape), do: []

  defp build_out_chars([]), do: []
  defp build_out_chars(out_queue), do: [{:out_chars, Enum.reverse(out_queue)}]
end
