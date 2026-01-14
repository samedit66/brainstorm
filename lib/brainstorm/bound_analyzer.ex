defmodule Brainstorm.BoundAnalyzer do
  @default_bound 100_000

  def max_bound(commands), do: do_max_bound(commands, 0)

  def do_max_bound([:in | _rest], _cursor), do: @default_bound
end
