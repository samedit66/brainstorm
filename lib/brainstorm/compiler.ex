defmodule Brainstorm.Compiler do
  alias Brainstorm.{Parser, Optimizer, Executor}

  def run(:int, file_path, _backend, _ext, _out_dir, opt_level, max_steps) do
    interpret(file_path, opt_level, max_steps)
  end

  def run(:comp, file_path, backend, ext, out_dir, opt_level, max_steps) do
    compile(file_path, backend, ext, out_dir, opt_level, max_steps)
  end

  def interpret(file_path, opt_level, max_steps) do
    with {:ok, bf_code} <- read_input_file(file_path),
         {:ok, parsed} <- parse(bf_code),
         optimized <- Optimizer.optimize(parsed, opt_level),
         :ok <- execute(optimized, :int, max_steps) do
      :ok
    end
  end

  def compile(file_path, backend, ext, out_dir, opt_level, max_steps) do
    with {:ok, bf_code} <- read_input_file(file_path),
         {:ok, parsed} <- parse(bf_code),
         optimized <- optimize(parsed, opt_level),
         {:ok, compiled} <- execute(optimized, :comp, max_steps),
         program <- backend.(compiled),
         :ok <- create_out_dir(out_dir),
         output_file <- output_file_path(file_path, ext, out_dir),
         :ok <- write_output_file(output_file, program) do
      :ok
    end
  end

  defp read_input_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, reason} ->
        {:error, "I couldn't read from '#{file_path}': #{:file.format_error(reason)}"}
    end
  end

  defp parse(bf_code) do
    case Parser.parse(bf_code) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, :missing_loop_start} ->
        {:error, "I noticed an unexpected right bracket"}

      {:error, :unclosed_loop} ->
        {:error, "I noticed some of loop was not closed properly with a right bracket"}
    end
  end

  defp optimize(commands, opt_level) do
    Optimizer.optimize(commands, opt_level)
  end

  defp execute(commands, mode, max_steps) do
    case Executor.run(commands, mode, max_steps) do
      :ok ->
        :ok

      {:compiled, compiled} ->
        {:ok, compiled}

      {:error, :hit_step_limit} ->
        {:error,
         "Hit maximum step limit. Possible infinite loop? Try increasing max steps or compiling"}
    end
  end

  defp create_out_dir(out_dir) do
    case File.mkdir_p(out_dir) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, "I couldn't create '#{out_dir}': #{:file.format_error(reason)}'"}
    end
  end

  defp write_output_file(file_path, content) do
    case File.write(file_path, content) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, "I couldn't write to '#{file_path}': #{:file.format_error(reason)}'"}
    end
  end

  defp output_file_path(input_file_path, ext, out_dir) do
    basename = Path.basename(input_file_path) |> Path.rootname()
    output_file_name = "#{basename}.#{ext}"
    Path.join(out_dir, output_file_name)
  end
end
