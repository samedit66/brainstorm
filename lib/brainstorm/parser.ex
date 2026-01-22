defmodule Brainstorm.Parser do
  @tokens [
    ">",
    "<",
    "+",
    "-",
    ".",
    ",",
    "[",
    "]"
  ]

  @doc ~S"""
  Parses given brainfuck `code` into intermediate representation.
  Cleans up `code`, removing any non-brainfuck tokens.

  ## Examples

      iex> Brainstorm.Parser.parse("+")
      {:ok, [{:inc, 1, 0}]}

      iex> Brainstorm.Parser.parse("-")
      {:ok, [{:inc, -1, 0}]}

      iex> Brainstorm.Parser.parse(">")
      {:ok, [shift: 1]}

      iex> Brainstorm.Parser.parse("<")
      {:ok, [shift: -1]}

      iex> Brainstorm.Parser.parse(".")
      {:ok, [out: 0]}

      iex> Brainstorm.Parser.parse(",")
      {:ok, [in: 0]}

      iex> Brainstorm.Parser.parse("[]")
      {:ok, [loop: []]}

      iex> Brainstorm.Parser.parse("[-]")
      {:ok, [{:loop, [{:inc, -1, 0}]}]}

      iex> Brainstorm.Parser.parse("This will be deleted")
      {:ok, []}

      iex> Brainstorm.Parser.parse("here we go: +++[->+<]")
      {:ok, [{:inc, 3, 0}, {:loop, [{:inc, -1, 0}, {:shift, 1}, {:inc, 1, 0}, {:shift, -1}]}]}

  Invalid brainfuck code results in an error:

      iex> Brainstorm.Parser.parse("[")
      {:error, :unclosed_loop}

      iex> Brainstorm.Parser.parse("]")
      {:error, :missing_loop_start}

  """
  def parse(code) do
    cleaned = code |> String.graphemes() |> clean()

    case do_parse(cleaned, []) do
      {:error, reason} -> {:error, reason}
      ast -> {:ok, ast}
    end
  end

  defp clean(chars),
    do: chars |> Enum.filter(&Enum.member?(@tokens, &1))

  defp do_parse([], commands), do: Enum.reverse(commands)

  defp do_parse(["." | rest], commands),
    do: do_parse(rest, [{:out, 0} | commands])

  defp do_parse(["," | rest], commands),
    do: do_parse(rest, [{:in, 0} | commands])

  defp do_parse(["[" | rest], commands) do
    case extract_loop(rest, [], 1) do
      {:error, reason} ->
        {:error, reason}

      {:ok, body, rest} ->
        do_parse(rest, [{:loop, do_parse(body, [])} | commands])
    end
  end

  defp do_parse(["]" | _rest], _commands), do: {:error, :missing_loop_start}

  defp do_parse(["+" | _rest] = tokens, commands) do
    {count, rest} = cut_and_count(tokens, "+")
    do_parse(rest, [{:inc, count, 0} | commands])
  end

  defp do_parse(["-" | _rest] = tokens, commands) do
    {count, rest} = cut_and_count(tokens, "-")
    do_parse(rest, [{:inc, -count, 0} | commands])
  end

  defp do_parse([">" | _rest] = tokens, commands) do
    {count, rest} = cut_and_count(tokens, ">")
    do_parse(rest, [{:shift, count} | commands])
  end

  defp do_parse(["<" | _rest] = tokens, commands) do
    {count, rest} = cut_and_count(tokens, "<")
    do_parse(rest, [{:shift, -count} | commands])
  end

  defp cut_and_count(tokens, token) do
    {repeated, rest} = tokens |> Enum.split_while(&(&1 == token))
    {Enum.count(repeated), rest}
  end

  defp extract_loop(["[" | rest], loop_tokens, bracket_level),
    do: extract_loop(rest, ["[" | loop_tokens], bracket_level + 1)

  defp extract_loop(["]" | rest], loop_tokens, 1),
    do: {:ok, Enum.reverse(loop_tokens), rest}

  defp extract_loop(["]" | rest], loop_tokens, bracket_level),
    do: extract_loop(rest, ["]" | loop_tokens], bracket_level - 1)

  defp extract_loop([token | rest], loop_tokens, bracket_level),
    do: extract_loop(rest, [token | loop_tokens], bracket_level)

  defp extract_loop([], _loop_tokens, bracket_level) when bracket_level >= 1,
    do: {:error, :unclosed_loop}
end
