# Brainfuck Compiler

An **optimized compiler for Brainfuck**, written in Elixir.  

I love compilers and Elixir, but I didn’t want to write a huge parser or tokenizer and die from boredom. Brainfuck is small, simple, and lets me focus entirely on optimizations.  

This compiler takes Brainfuck code and produces optimized C programs that can be compiled and run.  

---

## Quick Example

```bash
$ cat bf_snippets/hello.bf
# >+++++++++[<++++++++>-]<.>+++++++[<++++>-]<+.+++++++..+++.>>>++++++++[<++++>-]<.>>>++++++++++[<+++++++++>-]<---.<<<<.+++.------.--------.>>+.>++++++++++.
```

### Compile Brainfuck to C
```bash
$ ./brainfuck bf_snippets/hello.bf
```

Now we have `hello.c`.

### The generated C program

```c
#include <stdio.h>

int main(void) {
  fputs("Hello World!\n", stdout);

  return 0;
}
```

You can then compile and run the generated C code:

```bash
gcc -o hello hello.c
./hello
# Output: Hello World!
```

---

## Optimizations

The compiler applies several optimization techniques to make Brainfuck code faster and more readable in the generated C:

- **Combine sequential increments/decrements**  
  `+++--` becomes `+`.

- **Combine sequential shifts**  
  `>>>><<` becomes `>>`.

- **Remove dead loops at the start of the program**  
  `[+->><.>]++` becomes `++`.

- **Remove redundant sequential loops**  
  `[>][<]` becomes `[>]`.

- **Remove dead code at the end**  
  `+++++.>>><-` becomes `+++++.`  
  *Current limitation: dead loops are not automatically removed.*

- **Combine increments and shifts into single instructions**  
  Optimizes patterns like `+>+>` into fewer operations.

- **Detect and replace "multiplication loops"**  
  Loops that copy or scale values are replaced with direct arithmetic:  
  ```bf
  >+++++++++[<++++++++>-].
  ```
  becomes
  ```c
  arr[i + 1] = 9;
  i += 1;
  arr[i - 1] += arr[i] * 8;
  arr[i] = 0;
  ```

---

### Optimization Levels

You can control which optimizations are applied using the `opt_level` argument:

- `:o0` - No optimizations (original commands are returned as-is)  
- `:o1` - Basic peephole optimizations  
- `:o2` - Full optimizations (`:o1` plus removing trivial loops at start/end, fusing instructions, and unwrapping multiplication loops)  

---

## Installation

```bash
git clone https://github.com/samedit66/brainfuck.git
cd brainfuck
mix escript.build
./brainfuck
```

---

## Usage

```bash
./brainfuck <file.bf> [--opt-level 0|1|2] [--outdir <dir>]
```

**Options:**

- `--opt-level` (`-O`, `-o`) - Set optimization level (`0`, `1`, or `2`, default `2`)  
- `--outdir` - Directory to write the generated C file (default: current directory)
