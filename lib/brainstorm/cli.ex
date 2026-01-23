defmodule Brainstorm.CLI do
  alias Brainstorm.Compiler
  alias Brainstorm.Backend.C, as: C

  @compiler_name "bs"
  @no_input_message "No input file provided.\n\nUsage: #{@compiler_name} <file.bf> [-O0|O1|O2] [--outdir <dir>] [--mode <mode>] [--max-steps <steps]"

  def main(args \\ []) do
    with {:ok, {file, opt_level, out_dir, mode, max_steps}} <- parse_args(args),
         :ok <- Compiler.run(mode, file, &C.render/1, "c", out_dir, opt_level, max_steps) do
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
        strict: [opt_level: :integer, outdir: :string, mode: :string, max_steps: :string]
      )

    with {:ok, file} <- parse_input_file(files),
         {:ok, out_dir} <- parse_out_dir(opts[:out_dir]),
         {:ok, opt_level} <- parse_opt_level(opts[:opt_level]),
         {:ok, mode} <- parse_exec_mode(opts[:mode]),
         {:ok, max_steps} <- parse_max_steps(opts[:max_steps]) do
      {:ok, {file, opt_level, out_dir, mode, max_steps}}
    end
  end

  defp parse_input_file([]), do: {:error, @no_input_message}
  defp parse_input_file([first | _rest]), do: {:ok, first}

  defp parse_out_dir(nil), do: {:ok, "."}
  defp parse_out_dir(dir), do: {:ok, dir}

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

  defp parse_exec_mode(nil), do: {:ok, :int}
  defp parse_exec_mode("i"), do: {:ok, :int}
  defp parse_exec_mode("c"), do: {:ok, :comp}

  defp parse_exec_mode(other),
    do:
      {:error,
       """
       Invalid execution mode: #{inspect(other)}

       Expected one of:
         c   compilation
         i   interpretation
       """}

  defp parse_max_steps(nil), do: {:ok, 8192}
  defp parse_max_steps("infinity"), do: {:ok, :infinity}

  defp parse_max_steps(max_steps) do
    case Integer.parse(max_steps) do
      {number, _tail} when number > 0 ->
        {:ok, number}

      :error ->
        {:error,
         """
         Invalid max steps: must be a positive integer or infinity
         """}
    end
  end
end
