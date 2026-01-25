List directory contents using ls. The working directory is the project directory by default.
To list other directories, provide the directory path as an argument.
Common usage: ["."] to list current directory, ["-la", "src/"] to list with details in src directory,
or ["-R", "."] to recursively list all subdirectories.

@title List Directory Contents
@name LS
@wrapped run_command
@command ls {arguments}
@param arguments {array<string>} [required] Array of strings that will be passed to the ls command
