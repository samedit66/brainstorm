# brainstorm

An **optimizing compiler / interpreter for Brainfuck**, written in Elixir.  

I love compilers and Elixir, but I didn’t want to write a huge parser or tokenizer and die from boredom. Brainfuck is small, simple, and lets me focus entirely on optimizations.  

`brainstorm` is fully capable of interpreting `Brainfuck` code, as well as producing optimized `C` programs.

---

## Quick Example

```bash
cat bf_snippets/hello.bf
# >+++++++++[<++++++++>-]<.>+++++++[<++++>-]<+.+++++++..+++.>>>++++++++[<++++>-]<.>>>++++++++++[<+++++++++>-]<---.<<<<.+++.------.--------.>>+.>++++++++++.
```

### Interpret Brainfuck

```bash
./bs bf_snippets/hello.bf
# Output: Hello World!
```

### Compile Brainfuck to C
```bash
./bs bf_snippets/hello.bf --mode c
```

Now we have `hello.c`:

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

`brainstorm` supports a wide range of common Brainfuck optimizations, including nearly all of the techniques described in the notable article [brainfuck optimization strategies](http://calmerthanyouare.org/2015/01/07/optimizing-brainfuck.html).

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

- **Compile-time execution**

  `brainstorm` tries to execute code at compile-time as much as possible. To prevent an infinite time of compilation due to an unexpected infinite loop, `brainstorm` supports specifying steps limit - how many commands are allowed to be executed at compile-time. It defaults to `8192` and can be changed via `--max-steps` CLI argument. If you are risky enough, you can specify `--max-steps infinity` and wait as long as you want.

---

## Optimization Levels

You can control which optimizations are applied using the `opt_level` argument:

- `0` - No optimizations (original commands are returned as-is)  
- `1` - Basic peephole optimizations  
- `2` - Full optimizations (`:o1` plus removing trivial loops at start/end, fusing instructions, and unwrapping multiplication loops)  

---

## Examples

```bash
# Compile-time "Hello World!"
./bs ./bf_snippets/hello.bf --mode c

# Compile-time calculating squares or numbers from 1 to 1000
./bs ./bf_snippets/squares.bf --mode c --max-steps 1000000

# Run-time "Just another brainfuck hacker,"
./bs ./bf_snippets/jabh.bf

# A ghost game
./bs ./bf_snippets/ghost.bf --mode c
```

---

## Installation

```bash
git clone https://github.com/samedit66/brainstorm.git
cd brainstorm
mix escript.build
./bs
```

---

## Usage

```bash
./bs <file.bf> [--opt-level 0|1|2] [--outdir <dir>] [--mode i|c] [--max-steps <number>|infinity]
```

**Options:**

- `--opt-level` (`-O`, `-o`) - Set optimization level (`0`, `1`, or `2`, default `2`)  
- `--outdir` - Directory to write the generated C file (default: current directory)
- `--mode` - Execution mode (`i` - interpretation or `c` - compilation, default `i`)
- `--max-steps` - Maximum execution steps (any positive number or `infinity`, default `8192`)
