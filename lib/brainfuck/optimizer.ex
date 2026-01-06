defmodule Brainfuck.Optimizer do
  @doc """
  Optimizes given `ast`.
  The following optimization techniques are used:
  - Squeezes sequences like `+++.` into just `.`.
  - Combines sequentional increments and decrements into a single instruction:
    `+++--` becomes `+`.
  - Does the same for shifting: `>>>><<` becomes `>>`.
  - Drops dead loops at the very beggining of the program, when all cells are zero:
    `[+->><.>]++` becomes just `++`.
    Also, it removes loops in the following scenario:
    `>>>[+->>]++` becomes `++`.
  - Removes sequentional loops: `[>][<]` becomes `[>]`.
  - Drops dead code at the end: `+++++.>>><-` becomes `+++++.`.
    Current limitation: does not drop dead loops.

  ## Examples

      iex> Brainfuck.Optimizer.optimize([{:inc, 10}, {:inc, -4}, :out])
      [{:inc_offset, 6, 0}, :out]

  Note, that if you run `optimize` on the code which has not IO,
  you'll see nothing:

      iex> Brainfuck.Optimizer.optimize([{:inc, 10}, {:inc, -4}])
      []

  It's not a bug: no IO happens, no interactions with user, no computations performed.

  """
  def optimize(commands) do
    commands
    |> peephole_optimize([])
    |> remove_redundant(:at_start)
    |> remove_redundant(:at_end)

    # After `fuse` we need to apply peephole optimizations again,
    # because sometimes `fuse` may generate a code like this: `[{:shift, 2}, {:shift, -2}]`.
    # Example: `+[>-<->>+++<<].`.
    |> fuse([])
    |> peephole_optimize([])
    |> unwrap_loops([])
  end

  defp peephole_optimize([], optimized),
    do: Enum.reverse(optimized)

  defp peephole_optimize([:zero, :in | rest], optimized),
    do: peephole_optimize([:in | rest], optimized)

  defp peephole_optimize([:zero, {:inc, _n} = inc | rest], optimized),
    do: peephole_optimize([inc | rest], optimized)

  defp peephole_optimize([:zero, {:loop, _body} | rest], optimized),
    do: peephole_optimize([:zero | rest], optimized)

  defp peephole_optimize([{:inc, _n}, :zero | rest], optimized),
    do: peephole_optimize([:zero | rest], optimized)

  defp peephole_optimize([{:inc, n}, {:inc, m} | rest], optimized),
    do: peephole_optimize([{:inc, n + m} | rest], optimized)

  defp peephole_optimize([{:inc, 0} | rest], optimized),
    do: peephole_optimize(rest, optimized)

  defp peephole_optimize([{:inc, _n}, :in | rest], optimized),
    do: peephole_optimize([:in | rest], optimized)

  defp peephole_optimize([{:shift, 0} | rest], optimized),
    do: peephole_optimize(rest, optimized)

  defp peephole_optimize([{:shift, n}, {:shift, m} | rest], optimized),
    do: peephole_optimize([{:shift, n + m} | rest], optimized)

  defp peephole_optimize([{:loop, _b1} = first, {:loop, _b2} | rest], optimized),
    do: peephole_optimize([first | rest], optimized)

  defp peephole_optimize([{:loop, body} | rest], optimized),
    do:
      peephole_optimize(
        rest,
        [{:loop, peephole_optimize(body, [])} | optimized]
      )

  defp peephole_optimize([command | rest], optimized),
    do: peephole_optimize(rest, [command | optimized])

  defp remove_redundant([{:shift, _n}, {:loop, _body} | rest], :at_start),
    do: remove_redundant(rest, :at_start)

  defp remove_redundant(commands, :at_start),
    do: commands |> Enum.drop_while(&match?({:loop, _body}, &1))

  defp remove_redundant(commands, :at_end) do
    commands
    |> Enum.reverse()
    |> Enum.drop_while(fn
      :in -> false
      :out -> false
      # TODO: add a check that a loop is dead
      {:loop, _body} -> false
      _ -> true
    end)
    |> Enum.reverse()
  end

  defp fuse([], optimized), do: Enum.reverse(optimized)

  defp fuse(
         [{:shift, offset1}, {:inc, by1} | rest],
         [{:inc_offset, _by2, offset2} | _optimized_rest] = optimized
       ) do
    fuse(rest, [{:inc_offset, by1, offset1 + offset2} | optimized])
  end

  defp fuse([{:shift, offset}, {:inc, by} | rest], optimized) do
    fuse(rest, [{:inc_offset, by, offset} | optimized])
  end

  defp fuse([{:inc, by} | rest], optimized) do
    fuse(rest, [{:inc_offset, by, 0} | optimized])
  end

  defp fuse([{:loop, body} | rest], optimized) do
    fuse(rest, [{:loop, fuse(body, [])} | optimized])
  end

  defp fuse(
         [command | rest],
         [{:inc_offset, _by, offset} | _optimized_rest] = optimized
       ) do
    fuse(rest, [command, {:shift, offset} | optimized])
  end

  defp fuse([command | rest], fused), do: fuse(rest, [command | fused])

  defp unwrap_loops([], optimized), do: Enum.reverse(optimized)

  defp unwrap_loops([{:loop, body} | rest], optimized) do
    case parse_mults(body) do
      :failed ->
        unwrap_loops(rest, [{:loop, unwrap_loops(body, [])} | optimized])

      {:ok, mults} ->
        unwrap_loops(rest, [:zero] ++ mults ++ optimized)
    end
  end

  defp unwrap_loops([command | rest], optimized) do
    unwrap_loops(rest, [command | optimized])
  end

  defp parse_mults(commands) do
    {candidates, others} =
      commands
      |> Enum.split_with(&match?({:inc_offset, _by, _offset}, &1))

    {decrements, increments} =
      candidates
      |> Enum.split_with(&match?({:inc_offset, -1, 0}, &1))

    # A multiplication loop consists only of:
    # - only one decrement
    # - one or more increment of some cell
    case {others, decrements, increments} do
      {[], [_decrement], [_first | _rest]} ->
        {
          :ok,
          increments
          |> Enum.map(fn {:inc_offset, by, offset} -> {:mult_offset, by, offset} end)
        }

      _ ->
        :failed
    end
  end
end
