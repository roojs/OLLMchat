Find files matching glob patterns using find. The working directory is the project directory by default.
To search in other directories, provide the directory path as the first argument.
This tool uses find with -type f to find only files.
Common usage: ["-name", "*.vala"] to find all .vala files,
or ["src/", "-name", "*.json"] to find JSON files in src directory.

@title Glob Pattern Matching
@name Glob
@wrapped run_command
@command find {arguments} -type f
@example {"name": "Glob", "arguments": {"arguments": ["-name", "*.vala"]}}
@param arguments {array<string>} [required] Array of strings that will be passed to the command
