defmodule Brainstorm.Backend.C do
  @moduledoc """
  Generate a C program from IR commands.
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

  @spaces_per_level 2

  def render(out_chars: chars) do
    lines = render_sequence([{:out_chars, chars}], 1)

    (@short_prologue ++ lines ++ @default_epilogue)
    |> Enum.join("\n")
  end

  def render(commands) do
    lines = render_sequence(commands, 1)

    (@default_prologue ++ lines ++ @default_epilogue)
    |> Enum.join("\n")
  end

  defp render_sequence(commands, indent_level) do
    commands
    |> Enum.map(&render_single/1)
    |> List.flatten()
    |> Enum.map(fn line ->
      String.duplicate(" ", indent_level * @spaces_per_level) <> line
    end)
  end

  defp render_single({:out_chars, chars}) do
    case as_literal(chars) do
      {:string, text} ->
        ["fputs(#{text}, stdout);"]

      {:char_array, array} ->
        ["char chars[] = #{array};", "fputs(chars, stdout);"]
    end
  end

  defp render_single({:init_tape, tape}) do
    tape
    |> Map.to_list()
    |> Enum.map(fn {index, value} ->
      "arr[#{index}] = #{value};"
    end)
  end

  defp render_single({:shift, offset}) when offset > 0 do
    ["i += #{offset};"]
  end

  defp render_single({:shift, offset}) when offset < 0 do
    ["i -= #{abs(offset)};"]
  end

  # TODO: rewrite it to something quicker someday
  defp render_single({:scan, offset}) do
    render_single({:loop, [shift: offset]})
  end

  defp render_single({:set, value}) do
    ["arr[i] = #{value};"]
  end

  defp render_single({:inc, by, offset}) when by > 0 do
    ["arr[#{index_expr(offset)}] += #{by};"]
  end

  defp render_single({:inc, by, offset}) when by < 0 do
    ["arr[#{index_expr(offset)}] -= #{abs(by)};"]
  end

  defp render_single({:mult, by, offset}) do
    ["arr[#{index_expr(offset)}] += arr[i] * #{by};"]
  end

  defp render_single({:div, by, offset}) do
    ["arr[#{index_expr(offset)}] += arr[i] / #{by};"]
  end

  defp render_single({:out, offset}) do
    ["putchar(arr[#{index_expr(offset)}]);"]
  end

  defp render_single({:in, offset}) do
    ["arr[#{index_expr(offset)}] = getchar();"]
  end

  defp render_single({:loop, body}) do
    [
      "while (arr[i]) {",
      render_sequence(body, 1),
      "}"
    ]
    |> List.flatten()
  end

  defp as_literal(chars) do
    if Enum.all?(chars, &valid_codepoint?/1) do
      s = chars |> Enum.map(&escape_char/1) |> Enum.join()
      {:string, "\"#{s}\""}
    else
      arr = chars |> Enum.map(&to_string/1) |> Enum.join(", ")
      {:char_array, "{ #{arr} }"}
    end
  end

  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?"), do: "\\\""

  defp escape_char(cp) when is_integer(cp) and cp >= 32 and cp <= 126 do
    <<cp::utf8>>
  end

  defp escape_char(cp) when is_integer(cp) and cp >= 0 and cp <= 0xFF do
    hex = Integer.to_string(cp, 16) |> String.pad_leading(2, "0")
    "\\x" <> hex
  end

  defp escape_char(_), do: "\\x00"

  # treat codepoints 1..0x10FFFF (excluding surrogate range) as eligible for string literal
  defp valid_codepoint?(cp) when is_integer(cp) and cp >= 1 and cp <= 0x10FFFF do
    not (cp >= 0xD800 and cp <= 0xDFFF)
  end

  defp valid_codepoint?(_), do: false

  defp index_expr(0), do: "i"
  defp index_expr(offset) when offset > 0, do: "i + #{offset}"
  defp index_expr(offset) when offset < 0, do: "i - #{abs(offset)}"
end
