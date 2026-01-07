defmodule Brainfuck.Compiler do
  @moduledoc """
  High-level compiler for Brainfuck programs.

  Parses source code, applies optimizations, executes code at compile time
  when possible, and generates a C program.
  """

  alias Brainfuck.Parser
  alias Brainfuck.Optimizer
  alias Brainfuck.CompileTimeExecutor
  alias Brainfuck.Backend.C, as: BackendC

  @doc """
  Compile Brainfuck source code into C.

  The pipeline is:
    1. Parse Brainfuck source
    2. Optimize the AST
    3. Execute some code at compile time (if possible)
    4. Generate C code

  Returns `{:ok, c_source, exec_result}` on success, or `{:error, reason}`.
  """
  def compile(code, opt_level \\ :o2) when is_binary(code) do
    with {:ok, commands} <- Parser.parse(code) do
      optimized = Optimizer.optimize(commands, opt_level)
      exec_result = CompileTimeExecutor.execute(optimized)
      c_source = BackendC.generate(exec_result)
      {:ok, c_source, exec_result}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compile a `.bf` file and save the generated C source.

  Options:
    * `:opt_level` – optimizer level (default: `:o2`)
    * `:out_dir` – output directory for the `.c` file
      (default: same directory as the input file)
  """
  def compile_file(bf_file, opts \\ []) when is_binary(bf_file) do
    opt_level = Keyword.get(opts, :opt_level, :o2)
    out_dir = Keyword.get(opts, :out_dir, Path.dirname(bf_file))

    result =
      with {:ok, source} <- File.read(bf_file),
           {:ok, c_source, exec_result} <- compile(source, opt_level),
           :ok <- File.mkdir_p(out_dir),
           base <- Path.rootname(Path.basename(bf_file)),
           c_file <- Path.join(out_dir, base <> ".c"),
           :ok <- File.write(c_file, c_source) do
        {:ok, c_file, exec_result}
      end

    normalize_compile_result(result, bf_file)
  end

  defp normalize_compile_result({:ok, _path, _exec} = ok, _bf_file),
    do: ok

  defp normalize_compile_result({:error, reason}, bf_file),
    do: {:error, format_compile_error(bf_file, reason)}

  defp normalize_compile_result(other, bf_file),
    do: {:error, format_compile_error(bf_file, other)}

  defp format_compile_error(bf_file, reason) do
    """
    ✖ Brainfuck compilation failed

    File:
      #{bf_file}

    What happened:
      #{inspect(reason)}

    Hints:
      • Check the Brainfuck syntax
      • Make sure the output directory is writable
      • Try a lower optimization level (:o0 or :o1)

    Don’t worry — the compiler believes in you 🙂
    """
  end
end
