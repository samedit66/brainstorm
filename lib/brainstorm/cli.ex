defmodule Brainstorm.CLI do
  alias Brainstorm.Compiler

  @compiler_name "bs"
  @no_input_message "No input file provided.\n\nUsage: #{@compiler_name} <file.bf> [-O0|O1|O2] [--outdir <dir>]"

  def main(args \\ []) do
    with {:ok, {file, opt_level, out_dir}} <- parse_args(args),
         {:ok, _c_file, _exec_result} <-
           Compiler.compile_file(file, opt_level: opt_level, out_dir: out_dir) do
      :ok
    else
      {:error, reason} ->
        IO.puts(:stderr, reason)
        System.halt(1)
    end
  end

  defp parse_args([]), do: {:error, @no_input_message}

  defp parse_args(args) do
    {opts, files, _unknown} =
      OptionParser.parse(
        args,
        aliases: [O: :opt_level, o: :opt_level],
        strict: [opt_level: :integer, outdir: :string]
      )

    out_dir = Keyword.get(opts, :outdir, ".")

    with {:ok, file} <- parse_input_file(files),
         {:ok, opt_level} <- parse_opt_level(opts[:opt_level]) do
      {:ok, {file, opt_level, out_dir}}
    end
  end

  defp parse_input_file([]), do: {:error, @no_input_message}
  defp parse_input_file([first | _rest]), do: {:ok, first}

  # default if not specified
  defp parse_opt_level(nil), do: {:ok, :o2}
  defp parse_opt_level(0), do: {:ok, :o0}
  defp parse_opt_level(1), do: {:ok, :o1}
  defp parse_opt_level(2), do: {:ok, :o2}

  defp parse_opt_level(other),
    do:
      {:error,
       """
       Invalid optimization level: #{inspect(other)}

       Expected one of:
         -O0   no optimization
         -O1   basic optimizations
         -O2   full optimizations
       """}
end
