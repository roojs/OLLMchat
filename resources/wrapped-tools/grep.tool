Search for patterns in files using grep. The working directory is the project directory by default.
This tool uses grep to search for text patterns in files.
Common usage: ["-r", "pattern", "."] to recursively search for "pattern" in the current directory,
or ["-r", "-n", "pattern", "src/"] to search with line numbers in the src directory.

@title Grep Pattern Search
@name Grep
@wrapped run_command
@command grep {arguments}
@param arguments {array<string>} [required] Array of strings that will be passed to the grep command
