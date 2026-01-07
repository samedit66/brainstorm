defmodule Brainfuck.Optimizer do
  @doc """
  Optimizes given `commands`.
  The following optimization techniques are used:
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
  - Combines increments and shifts into a signle command.
  - Recongnizes so called "multiplication loops" and replaces them with real multiplications:
    `>+++++++++[<++++++++>-].` becomes
    `arr[i + 1] = 9; i += 1; arr[i - 1] += arr[i] * 8; arr[i] = 0;`.

  You can control what optimizations are perfomed with `opt_level`:
  - `:o0` - no optimization (return original commands)
  - `:o1` - peephole optimization
  - `:o2` - full optimizations (`:o1`, remove trivial start/end, fuse and unwrap multiplication loops)

  ## Examples

      iex> Brainfuck.Optimizer.optimize([{:inc, 10, 0}, {:inc, -4, 0}], :o1)
      [{:inc, 6, 0}]

  Note that if you run default `optimize` (with `:o2` opt-level) on the code
  which has no IO, you won't see anything:

      iex> Brainfuck.Optimizer.optimize([{:inc, 10, 0}, {:inc, -4, 0}])
      []

  That's intentional: no IO happens, no interactions with user, no computations performed.

  """
  def optimize(commands, opt_level \\ :o2)

  def optimize(commands, :o0), do: commands

  def optimize(commands, :o1), do: commands |> peephole_optimize([])

  def optimize(commands, :o2) do
    commands
    |> optimize(:o1)
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

  defp peephole_optimize([:zero, {:inc, _by, 0} = inc | rest], optimized),
    do: peephole_optimize([inc | rest], optimized)

  defp peephole_optimize([:zero, {:loop, _body} | rest], optimized),
    do: peephole_optimize([:zero | rest], optimized)

  defp peephole_optimize([{:inc, _by, _offset}, :zero | rest], optimized),
    do: peephole_optimize([:zero | rest], optimized)

  defp peephole_optimize([{:inc, n, 0}, {:inc, m, 0} | rest], optimized),
    do: peephole_optimize([{:inc, n + m, 0} | rest], optimized)

  defp peephole_optimize([{:inc, 0, 0} | rest], optimized),
    do: peephole_optimize(rest, optimized)

  defp peephole_optimize([{:inc, _n, 0}, :in | rest], optimized),
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
         [{:shift, offset1}, {:inc, by1, 0} | rest],
         [{:inc, _by2, offset2} | _optimized_rest] = optimized
       ) do
    fuse(rest, [{:inc, by1, offset1 + offset2} | optimized])
  end

  defp fuse([{:shift, offset}, {:inc, by, 0} | rest], optimized) do
    fuse(rest, [{:inc, by, offset} | optimized])
  end

  defp fuse(
         [{:loop, _body} | _rest] = commands,
         [{:inc, _by, offset} | _optimized_rest] = optimized
       ) do
    fuse(commands, [{:shift, offset} | optimized])
  end

  defp fuse([{:loop, body} | rest], optimized) do
    fuse(rest, [{:loop, fuse(body, [])} | optimized])
  end

  defp fuse(
         [command | rest],
         [{:inc, _by, offset} | _optimized_rest] = optimized
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
      |> Enum.split_with(&match?({:inc, _by, _offset}, &1))

    {decrements, increments} =
      candidates
      |> Enum.split_with(&match?({:inc, -1, 0}, &1))

    # A multiplication loop consists only of:
    # - only one decrement
    # - one or more increment of some cell
    case {others, decrements, increments} do
      {[], [_decrement], [_first | _rest]} ->
        {
          :ok,
          increments
          |> Enum.map(fn {:inc, by, offset} -> {:mult, by, offset} end)
        }

      _ ->
        :failed
    end
  end
end
