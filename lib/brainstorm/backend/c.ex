defmodule Brainstorm.Backend.C do
  @moduledoc """
  Generate a C program.
  """

  @default_prologue [
    "#include <string.h>",
    "#include <stdio.h>",
    "",
    "int main(void) {",
    "  int i = 0;",
    "  char arr[30000];",
    "  memset(arr, 0, sizeof(arr));",
    ""
  ]

  @default_epilogue [
    "",
    "  return 0;",
    "}",
    ""
  ]

  @short_prologue [
    "#include <stdio.h>",
    "",
    "int main(void) {"
  ]

  @spaces_count_for_indent_level 2

  def generate(result)

  def generate({:full, %{out_queue: out_queue}}) do
    lines = parse_to_fputs(out_queue)

    (@short_prologue ++ indent(lines, 2) ++ @default_epilogue)
    |> Enum.join("\n")
  end

  def generate({:partial, %{i: i, tape: tape, out_queue: out_queue}, rest}) do
    tape_lines =
      tape
      |> Enum.filter(fn {_k, v} -> v != 0 end)
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {idx, val} -> "arr[#{idx}] = #{val};" end)

    pointer_line = "i = #{i};"
    out_lines = parse_to_fputs(out_queue)

    prelude = tape_lines ++ [pointer_line] ++ out_lines ++ [""]

    rest_lines = render(rest, 2)

    (@default_prologue ++ indent(prelude, 2) ++ rest_lines ++ @default_epilogue)
    |> Enum.join("\n")
  end

  defp parse_to_fputs(out_queue) do
    case parse_as_c_literal(out_queue) do
      {:string, "\"\""} ->
        []

      {:string, string} ->
        ["fputs(#{string}, stdout);"]

      {:char_array, char_array} ->
        ["char* text = #{char_array};", "fputs(text, stdout);"]
    end
  end

  defp parse_as_c_literal(out_queue) do
    if Enum.all?(out_queue, &valid_codepoint?/1) do
      string =
        out_queue
        |> Enum.map(&escape_c_char/1)
        |> Enum.join()

      {:string, "\"#{string}\""}
    else
      char_array = Enum.join(out_queue, ", ")
      {:char_array, "{ #{char_array} }"}
    end
  end

  defp escape_c_char(cp) do
    case cp do
      ?\n -> "\\n"
      ?\r -> "\\r"
      ?\t -> "\\t"
      ?\\ -> "\\\\"
      ?" -> "\\\""
      # printable ASCII
      cp when cp >= 32 and cp <= 126 -> <<cp::utf8>>
      # fallback for other Unicode codepoints
      cp -> "\\x" <> Integer.to_string(cp, 16)
    end
  end

  defp valid_codepoint?(cp) when is_integer(cp) and cp >= 1 and cp <= 0x10FFFF do
    not (cp >= 0xD800 and cp <= 0xDFFF)
  end

  defp valid_codepoint?(_cp), do: false

  defp render([], _level), do: []

  defp render(commands, level) when is_list(commands) do
    Enum.flat_map(commands, &render_cmd(&1, level))
  end

  defp render_cmd(:out, level), do: [indent("putchar(arr[i]);", level)]

  defp render_cmd(:in, level), do: [indent("arr[i] = getchar();", level)]

  defp render_cmd({:set, value}, level), do: [indent("arr[i] = #{value};", level)]

  defp render_cmd({:inc, 0, _offset}, _level), do: []

  defp render_cmd({:inc, by, offset}, level) do
    idx = index_expr(offset)

    op =
      if by > 0,
        do: "arr[#{idx}] += #{by};",
        else: "arr[#{idx}] -= #{abs(by)};"

    [indent(op, level)]
  end

  defp render_cmd({:shift, 0}, _level), do: []

  defp render_cmd({:shift, n}, level) do
    line =
      if n > 0,
        do: "i += #{n};",
        else: "i -= #{abs(n)};"

    [indent(line, level)]
  end

  # This probably never happens though
  defp render_cmd({:mult, 0, _offset}, _level), do: []

  defp render_cmd({:mult, by, offset}, level) do
    idx = index_expr(offset)

    line =
      if by > 0,
        do: "arr[#{idx}] += arr[i] * #{by};",
        else: "arr[#{idx}] -= arr[i] * #{abs(by)};"

    [indent(line, level)]
  end

  defp render_cmd({:div, by, offset}, level) do
    idx = index_expr(offset)

    line =
      if by > 0,
        do: "arr[#{idx}] += arr[i] / #{by};",
        else: "arr[#{idx}] -= arr[i] / #{abs(by)};"

    [indent(line, level)]
  end

  defp render_cmd({:loop, body}, level) do
    open = indent("while (arr[i]) {", level)
    body = render(body, level + @spaces_count_for_indent_level)
    close = indent("}", level)
    [open] ++ body ++ [close]
  end

  defp render_cmd({:scan, n}, level) do
    # Currently, I do not want to implement this in an efficeint way...
    # Nonetheless, I plan to do it soon
    render_cmd({:loop, [shift: n]}, level)
  end

  defp index_expr(0), do: "i"
  defp index_expr(offset) when offset > 0, do: "i + #{offset}"
  defp index_expr(offset) when offset < 0, do: "i - #{abs(offset)}"

  defp indent(line, level) when is_binary(line) do
    String.duplicate(" ", level) <> line
  end

  defp indent(lines, level) do
    Enum.map(lines, &indent(&1, level))
  end
end
