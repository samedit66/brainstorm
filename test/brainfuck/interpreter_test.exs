defmodule Brainfuck.InterpreterTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias Brainstorm.{Parser, Executor}

  test "outputs \"Hello World!\"" do
    hello_world = """
    >+++++++++[<++++++++>-]<.>+++++++[<++++>-]<+.+++++++..+++.>>>++++++++[<++++>-]<.>>>++++++++++[<+++++++++>-]<---.<<<<.+++.------.--------.>>+.>++++++++++.
    """

    {:ok, commands} = Parser.parse(hello_world)
    assert capture_io(fn -> Executor.run(commands, mode: :int) end) == "Hello World!\n"
    assert Executor.run(commands, mode: :comp) == {:compiled, [out_chars: ~c"Hello World!\n"]}
  end
end
