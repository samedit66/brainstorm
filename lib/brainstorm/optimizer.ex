defmodule Brainstorm.Optimizer do
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

      iex> Brainstorm.Optimizer.optimize([{:inc, 10, 0}, {:inc, -4, 0}], :o1)
      [{:inc, 6, 0}]

      iex> Brainstorm.Optimizer.optimize([
      ...>   {:inc, 1, 0},
      ...>   {:loop, [
      ...>     {:inc, -1, 0},
      ...>     {:shift, 1}, {:inc, 8, 0},
      ...>     {:shift, -2}, {:inc, -2, 0},
      ...>     {:shift, 1}
      ...>   ]},
      ...>   {:out, 0}
      ...> ], :o2)
      [{:inc, 1, 0}, {:div, 2, -1}, {:mult, 8, 1}, {:set, 0}, {:out, 0}]

  Note that if you run default `optimize` (with `:o2` opt-level) on the code
  which has no IO, you won't see anything:

      iex> Brainstorm.Optimizer.optimize([{:inc, 10, 0}, {:inc, -4, 0}])
      []

  That's intentional: no IO happens, no interactions with user, no computations performed.

  """
  def optimize(commands, opt_level \\ :o2)

  def optimize(commands, :o0), do: commands

  def optimize(commands, :o1), do: commands |> peephole_optimize()

  def optimize(commands, :o2) do
    commands
    |> optimize(:o1)
    |> remove_redundant(:at_start)
    |> remove_redundant(:at_end)

    # After `fuse` we need to apply peephole optimizations again,
    # because sometimes `fuse` may generate a code like this: `[{:shift, 2}, {:shift, -2}]`.
    # Example: `+[>-<->>+++<<].`.
    |> fuse()
    |> peephole_optimize()
    |> unwrap_loops()
    |> peephole_optimize()
    |> scan_loops()
    |> peephole_optimize()
  end

  defp peephole_optimize(commands), do: peephole_optimize(commands, [])

  defp peephole_optimize([], optimized), do: Enum.reverse(optimized)

  defp peephole_optimize([{:set, 0}, {:in, 0} | rest], optimized),
    do: peephole_optimize([{:in, 0} | rest], optimized)

  defp peephole_optimize([{:set, 0}, {:inc, by, 0} | rest], optimized),
    do: peephole_optimize([{:set, by} | rest], optimized)

  defp peephole_optimize([{:set, 0}, {:loop, _body} | rest], optimized),
    do: peephole_optimize([{:set, 0} | rest], optimized)

  defp peephole_optimize([{:inc, _by, _offset}, {:set, 0} | rest], optimized),
    do: peephole_optimize([{:set, 0} | rest], optimized)

  defp peephole_optimize([{:inc, n, 0}, {:inc, m, 0} | rest], optimized),
    do: peephole_optimize([{:inc, n + m, 0} | rest], optimized)

  defp peephole_optimize([{:inc, 0, 0} | rest], optimized),
    do: peephole_optimize(rest, optimized)

  defp peephole_optimize([{:inc, _n, 0}, {:in, 0} | rest], optimized),
    do: peephole_optimize([{:in, 0} | rest], optimized)

  defp peephole_optimize([{:shift, 0} | rest], optimized),
    do: peephole_optimize(rest, optimized)

  defp peephole_optimize([{:shift, n}, {:shift, m} | rest], optimized),
    do: peephole_optimize([{:shift, n + m} | rest], optimized)

  defp peephole_optimize([{:loop, _b1} = first, {:loop, _b2} | rest], optimized),
    do: peephole_optimize([first | rest], optimized)

  # The following optimization sometimes may result in an unexpected result:
  # `-[-].` should cause an infinite loop because all cells are zero, we subtract 1
  # and get -1 at cell #0. Next goes infinite loop which subtracts until it reaches zero.
  # This optimization removes this loop and just sets cell #0 to zero.
  # How to prevent it? Compile with `:o0` level...
  # UPDATE 13.01.2026: found out that any Brainfuck implemntation
  # should set cell to 0 when overflow happens.
  defp peephole_optimize([{:loop, [{:inc, by, _offset}]} | rest], optimized) when abs(by) == 1 do
    peephole_optimize(rest, [{:set, 0} | optimized])
  end

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
      {:in, _offset} -> false
      {:out, _offset} -> false
      # TODO: add a check that a loop is dead
      {:loop, _body} -> false
      _ -> true
    end)
    |> Enum.reverse()
  end

  defp fuse(commands), do: fuse(commands, [], 0)

  defp fuse([], optimized, 0), do: Enum.reverse(optimized)

  defp fuse([], optimized, cursor) do
    Enum.reverse([{:shift, cursor} | optimized])
  end

  defp fuse([{:shift, offset} | rest], optimized, cursor) do
    fuse(rest, optimized, cursor + offset)
  end

  defp fuse([{:inc, by, 0} | rest], optimized, cursor) do
    fuse(rest, [{:inc, by, cursor} | optimized], cursor)
  end

  defp fuse([{:loop, body} | rest], optimized, cursor) do
    fuse(rest, [{:loop, fuse(body)}, {:shift, cursor} | optimized], 0)
  end

  defp fuse([{:out, 0} | rest], optimized, cursor) do
    fuse(rest, [{:out, cursor} | optimized], cursor)
  end

  defp fuse([{:in, 0} | rest], optimized, cursor) do
    fuse(rest, [{:in, cursor} | optimized], cursor)
  end

  defp fuse([command | rest], optimized, cursor) do
    fuse(rest, [command, {:shift, cursor} | optimized], 0)
  end

  defp unwrap_loops(commands), do: unwrap_loops(commands, [])

  defp unwrap_loops([], optimized), do: Enum.reverse(optimized)

  defp unwrap_loops([{:loop, body} | rest], optimized) do
    case parse_mults_and_divs(body) do
      :failed ->
        unwrap_loops(rest, [{:loop, unwrap_loops(body, [])} | optimized])

      {:ok, mults, divs} ->
        unwrap_loops(rest, [{:set, 0}] ++ mults ++ divs ++ optimized)
    end
  end

  defp unwrap_loops([command | rest], optimized) do
    unwrap_loops(rest, [command | optimized])
  end

  defp parse_mults_and_divs(commands) do
    {candidates, others} =
      commands
      |> Enum.split_with(&match?({:inc, _by, _offset}, &1))

    {decrements, increments} =
      candidates
      |> Enum.split_with(fn {:inc, by, _offset} -> by < 0 end)

    {loop_decrement, other_decrements} =
      decrements
      |> Enum.split_while(&match?({:inc, -1, 0}, &1))

    case {others, loop_decrement, other_decrements, increments} do
      {[], [_decrement], _decrements, _increments} ->
        mults =
          increments
          |> Enum.map(fn {:inc, by, offset} -> {:mult, by, offset} end)

        divs =
          other_decrements
          |> Enum.map(fn {:inc, by, offset} -> {:div, abs(by), offset} end)

        {:ok, mults, divs}

      _ ->
        :failed
    end
  end

  defp scan_loops(commands), do: scan_loops(commands, [])

  defp scan_loops([], optimized), do: Enum.reverse(optimized)

  defp scan_loops([{:loop, [shift: n]} | rest], optimized) do
    scan_loops(rest, [{:scan, n} | optimized])
  end

  defp scan_loops([{:loop, body} | rest], optimized) do
    scan_loops(rest, [{:loop, scan_loops(body)} | optimized])
  end

  defp scan_loops([command | rest], optimized), do: scan_loops(rest, [command | optimized])
end
