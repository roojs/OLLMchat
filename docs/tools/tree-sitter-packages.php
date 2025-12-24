#!/usr/bin/php
<?php
/**
 * 
 * # Install system dependencies
sudo apt update
sudo apt install -y \
    git \
    nodejs \
    npm \
    build-essential \
    devscripts \
    debhelper \
    libtree-sitter-dev \
    libc6-dev \
	tree-sitter-cli


 * 
 * 
 * 
 * Tree-sitter Parser Debian Package Builder
 * 
 * This script automates building Debian packages for Tree-sitter parsers
 * from various GitHub repositories.
 * 
 * Usage: php build-tree-sitter-packages.php [--install] [--clean]
 */

class TreeSitterPackageBuilder {
    
    // List of Tree-sitter parser repositories to package
    // Format: ['name' => 'package-name', 'repo' => 'github-url', 'language' => 'lang-name']
    private array $parsers = [
        // Popular languages
        'vala' => [
            'name' => 'tree-sitter-vala',
            'repo' => 'https://github.com/vala-lang/tree-sitter-vala',
            'language' => 'vala'
        ],
      
        'rust' => [
            'name' => 'tree-sitter-rust',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-rust',
            'language' => 'rust'
        ],
        'python' => [
            'name' => 'tree-sitter-python',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-python',
            'language' => 'python'
        ],
        'javascript' => [
            'name' => 'tree-sitter-javascript',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-javascript',
            'language' => 'javascript'
        ],
        'java' => [
            'name' => 'tree-sitter-java',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-java',
            'language' => 'java'
        ],
        'cpp' => [
            'name' => 'tree-sitter-cpp',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-cpp',
            'language' => 'cpp'
        ],
        'c-sharp' => [
            'name' => 'tree-sitter-c-sharp',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-c-sharp',
            'language' => 'c_sharp'
        ],
        'php' => [
            'name' => 'tree-sitter-php',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-php',
            'language' => 'php'
        ],
        'ruby' => [
            'name' => 'tree-sitter-ruby',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-ruby',
            'language' => 'ruby'
        ],
        'bash' => [
            'name' => 'tree-sitter-bash',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-bash',
            'language' => 'bash'
        ],
        // Add more as needed
		// stuff that fails
		'go' => [
            'name' => 'tree-sitter-go',
            'repo' => 'https://github.com/tree-sitter/tree-sitter-go',
            'language' => 'go'
        ],

    ];
    
    private string $baseDir;
    private bool $installPackages = false;
    private bool $cleanBeforeBuild = false;
    private array $results = [];
    
    public function __construct(string $baseDir = null) {
        $this->baseDir = $baseDir ?: $_SERVER['HOME'] . '/git';
        
        // Create base directory
        $this->createDirectory($this->baseDir);
        
        // Parse command line arguments
        $this->parseArguments();
    }
    
    private function parseArguments(): void {
        $options = getopt('', ['install', 'clean', 'help', 'list']);
        
        if (isset($options['help'])) {
            $this->showHelp();
            exit(0);
        }
        
        if (isset($options['list'])) {
            $this->listParsers();
            exit(0);
        }
        
        $this->installPackages = isset($options['install']);
        $this->cleanBeforeBuild = isset($options['clean']);
    }
    
    private function showHelp(): void {
        echo "Tree-sitter Parser Debian Package Builder\n";
        echo "========================================\n\n";
        echo "Usage: php " . basename(__FILE__) . " [OPTIONS]\n\n";
        echo "Options:\n";
        echo "  --install     Install packages after building\n";
        echo "  --clean       Clean before building (removes existing directories)\n";
        echo "  --list        List available parsers\n";
        echo "  --help        Show this help message\n\n";
        echo "Output directory: {$this->baseDir}\n";
    }
    
    private function listParsers(): void {
        echo "Available Tree-sitter parsers:\n";
        echo str_repeat('=', 40) . "\n";
        
        foreach ($this->parsers as $key => $parser) {
            echo sprintf(
                "%-15s %-25s %s\n",
                $key,
                $parser['name'],
                $parser['repo']
            );
        }
        
        echo "\nTotal: " . count($this->parsers) . " parsers\n";
    }
    
    /**
     * Build all packages
     */
    public function buildAll(): void {
        echo "Starting build process for " . count($this->parsers) . " parsers...\n";
        echo "Output directory: {$this->baseDir}\n\n";
        
        $startTime = microtime(true);
        
        foreach ($this->parsers as $key => $parser) {
            echo str_repeat('=', 60) . "\n";
            echo "Processing: {$parser['name']} ({$parser['language']})\n";
            echo str_repeat('-', 60) . "\n";
            
            try {
                $result = $this->buildPackage($parser);
                $this->results[$key] = $result;
                
                if ($result['success']) {
                    echo "✓ SUCCESS: {$parser['name']}\n";
                    
                    if ($this->installPackages && !empty($result['package_files'])) {
                        $this->installPackage($result['package_files']);
                    }
                } else {
                    echo "✗ FAILED: {$parser['name']} - {$result['error']}\n";
                    echo "\nFATAL: Build failed. Exiting.\n";
                    exit(1);
                }
            } catch (Exception $e) {
                echo "✗ ERROR: {$parser['name']}\n";
                echo "Error message: {$e->getMessage()}\n";
                echo "\nFATAL: Build failed. Exiting.\n";
                exit(1);
            }
            
            echo "\n";
        }
        
        $duration = microtime(true) - $startTime;
        $this->showSummary($duration);
    }
    
    /**
     * Build a single package
     */
    private function buildPackage(array $parser): array {
        $repoDir = $this->baseDir . '/' . $parser['name'];
        $buildDir = $repoDir . '/build';
        
        // Clean if requested
        if ($this->cleanBeforeBuild && is_dir($repoDir)) {
            echo "  Cleaning: Removing existing directory...\n";
            $this->executeCommand("rm -rf " . escapeshellarg($repoDir), true);
            echo "  ✓ Directory removed\n";
        }
        
        // Clone or update repository
        if (!is_dir($repoDir)) {
            echo "  Fetching: Cloning repository from {$parser['repo']}...\n";
            $this->executeCommand(
                "git clone " . escapeshellarg($parser['repo']) . " " . escapeshellarg($repoDir),
                true
            );
            echo "  ✓ Repository cloned successfully\n";
        } else {
            echo "  Fetching: Updating existing repository...\n";
            // Reset any local changes first
            $this->executeCommand(
                "cd " . escapeshellarg($repoDir) . " && git reset --hard",
                true
            );
            
            // Checkout master/main first to ensure we're on a branch (not a tag)
            // Check current branch/HEAD state
            $currentBranch = trim($this->executeCommand(
                "cd " . escapeshellarg($repoDir) . " && git symbolic-ref --short HEAD 2>/dev/null || echo 'DETACHED'",
                false
            ));
            
            if ($currentBranch === 'DETACHED' || empty($currentBranch)) {
                echo "    Currently on detached HEAD, checking out master/main...\n";
                
                // Check which branch exists (master or main)
                $masterExists = false;
                $mainExists = false;
                exec("cd " . escapeshellarg($repoDir) . " && git show-ref --verify --quiet refs/heads/master 2>/dev/null", $output, $returnCode);
                if ($returnCode === 0) {
                    $masterExists = true;
                }
                exec("cd " . escapeshellarg($repoDir) . " && git show-ref --verify --quiet refs/heads/main 2>/dev/null", $output, $returnCode);
                if ($returnCode === 0) {
                    $mainExists = true;
                }
                
                // Checkout the branch that exists
                if ($masterExists) {
                    $this->executeCommand(
                        "cd " . escapeshellarg($repoDir) . " && git checkout master",
                        true
                    );
                    echo "    ✓ Checked out master\n";
                } elseif ($mainExists) {
                    $this->executeCommand(
                        "cd " . escapeshellarg($repoDir) . " && git checkout main",
                        true
                    );
                    echo "    ✓ Checked out main\n";
                } else {
                    // No master or main branch - try to checkout the default branch from remote
                    $defaultBranch = trim($this->executeCommand(
                        "cd " . escapeshellarg($repoDir) . " && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo ''",
                        false
                    ));
                    if (!empty($defaultBranch)) {
                        $this->executeCommand(
                            "cd " . escapeshellarg($repoDir) . " && git checkout " . escapeshellarg($defaultBranch),
                            true
                        );
                        echo "    ✓ Checked out {$defaultBranch}\n";
                    } else {
                        echo "    Warning: No master/main branch found, staying on current HEAD\n";
                    }
                }
            }
            
            $this->executeCommand(
                "cd " . escapeshellarg($repoDir) . " && git fetch --tags",
                true
            );
            $this->executeCommand(
                "cd " . escapeshellarg($repoDir) . " && git pull",
                true
            );
            echo "  ✓ Repository updated successfully\n";
        }
        
        // Track which tag/version we're using for package versioning
        $packageVersion = null;
        $checkedOutTag = null;
        
        // For tree-sitter GitHub repos, checkout matching version tag
        if (strpos($parser['repo'], 'github.com/tree-sitter/') !== false) {
            $treeSitterVersion = $this->getTreeSitterVersion();
            if ($treeSitterVersion !== null) {
                echo "  Finding tag matching tree-sitter version: {$treeSitterVersion}\n";
                $matchingTag = $this->findMatchingTag($repoDir, $treeSitterVersion);
                
                if ($matchingTag !== null) {
                    // Reset to clean state before checking out tag
                    $this->executeCommand(
                        "cd " . escapeshellarg($repoDir) . " && git reset --hard",
                        true
                    );
                    $this->executeCommand(
                        "cd " . escapeshellarg($repoDir) . " && git checkout " . escapeshellarg($matchingTag),
                        true
                    );
                    echo "  ✓ Checked out tag: {$matchingTag}\n";
                    $checkedOutTag = $matchingTag;
                    
                    // Extract version from tag
                    $tagVersion = $this->extractVersionFromTag($matchingTag);
                    if ($tagVersion !== null && $tagVersion !== $treeSitterVersion) {
                        echo "  Using tag version {$tagVersion} (differs from tree-sitter {$treeSitterVersion})\n";
                        $packageVersion = $tagVersion;
                    } else {
                        $packageVersion = $treeSitterVersion;
                    }
                } else {
                    echo "  Warning: No matching tag found for version {$treeSitterVersion}, using current branch\n";
                    $packageVersion = $treeSitterVersion;
                }
            }
        }
        
        // Get current commit ID
        $currentCommit = trim($this->executeCommand(
            "cd " . escapeshellarg($repoDir) . " && git rev-parse HEAD",
            false
        ));
        
        // Check if package already exists for this commit
        $commitFile = $repoDir . '/debian_package_commit.txt';
        echo "  Checking for existing package...\n";
        echo "    Commit file: {$commitFile}\n";
        echo "    Current commit: {$currentCommit}\n";
        
        if (file_exists($commitFile)) {
            $savedCommit = trim(file_get_contents($commitFile));
            echo "    Saved commit: {$savedCommit}\n";
            
            if ($savedCommit === $currentCommit) {
                // Check if package files actually exist
                // Package names have 'lib' prefix: libtree-sitter-vala-*.deb
                $packageName = 'lib' . $parser['name'];
                $packagePattern = $this->baseDir . '/' . $packageName . '-*.deb';
                echo "    Checking for packages matching: {$packagePattern}\n";
                $existingPackages = glob($packagePattern);
                
                if (!empty($existingPackages)) {
                    echo "  ✓ Skipping: Package already built for commit {$currentCommit}\n";
                    echo "    Found existing packages: " . count($existingPackages) . "\n";
                    foreach ($existingPackages as $pkg) {
                        echo "      - " . basename($pkg) . "\n";
                    }
                    return [
                        'success' => true,
                        'package_files' => $existingPackages,
                        'build_dir' => $buildDir,
                        'repo_dir' => $repoDir,
                        'skipped' => true
                    ];
                } else {
                    echo "    Commit matches but package files missing, will rebuild\n";
                }
            } else {
                echo "    Commit changed: saved={$savedCommit}, current={$currentCommit}\n";
            }
        } else {
            echo "    No saved commit file found at: {$commitFile}\n";
            echo "    Will build new package\n";
        }
        
        echo "  Building package for commit: {$currentCommit}\n";
        
        // Check if it's a valid Tree-sitter parser
        // Some repos have multiple grammars in subdirectories (e.g., tree-sitter-typescript)
        $grammarDirs = $this->findGrammarDirectories($repoDir);
        
        if (empty($grammarDirs)) {
            throw new Exception("Not a valid Tree-sitter grammar (no grammar.js/grammar.json found in root or subdirectories)");
        }
        
        if (count($grammarDirs) > 1) {
            echo "  Found multiple grammars: " . count($grammarDirs) . "\n";
            foreach ($grammarDirs as $dir) {
                $dirName = basename($dir);
                echo "    - {$dirName}\n";
            }
            echo "  Will build all grammars into a single package\n";
        }
        
        // Get tree-sitter version for package versioning (use tag version if available)
        $treeSitterBin = $this->findTreeSitterBinary();
        if ($packageVersion === null) {
            $packageVersion = $this->getTreeSitterVersion() ?: '0.1.0';
        }
        
        // Check for existing package.json or create one
        if (!file_exists($repoDir . '/package.json')) {
            $this->createPackageJson($repoDir, $parser, $packageVersion);
        }
        
        // Install npm dependencies in repo directory if package.json exists and has dependencies
        // Some repos (like tree-sitter-typescript) need dependencies (including devDependencies) to build
        // Also, if dependencies reference other tree-sitter parsers we've built, try to link them
        if (file_exists($repoDir . '/package.json')) {
            $packageJson = json_decode(file_get_contents($repoDir . '/package.json'), true);
            if (!empty($packageJson['dependencies']) || !empty($packageJson['devDependencies'])) {
                echo "  Installing npm dependencies in repository (including devDependencies)...\n";
                
                // Check if any dependencies are tree-sitter parsers we might have built
                $allDeps = array_merge(
                    $packageJson['dependencies'] ?? [],
                    $packageJson['devDependencies'] ?? []
                );
                
                // Try to link local tree-sitter parser packages if they exist
                // This allows using locally built parsers instead of downloading from npm
                $localDeps = [];
                foreach ($allDeps as $depName => $depVersion) {
                    if (strpos($depName, 'tree-sitter-') === 0 && $depName !== 'tree-sitter-cli' && $depName !== 'tree-sitter') {
                        $depRepoDir = $this->baseDir . '/' . $depName;
                        if (is_dir($depRepoDir) && file_exists($depRepoDir . '/package.json')) {
                            echo "    Found local {$depName}, will link instead of downloading\n";
                            $localDeps[$depName] = $depRepoDir;
                        }
                    }
                }
                
                // Install dependencies
                // If we have local dependencies, install them first with file: protocol
                $installCmd = "cd " . escapeshellarg($repoDir) . " && npm install --include=dev";
                if (!empty($localDeps)) {
                    // Install local deps with file: protocol
                    foreach ($localDeps as $depName => $depPath) {
                        $installCmd .= " && npm install --include=dev " . escapeshellarg($depName . '@file:' . $depPath);
                    }
                }
                $this->executeCommand($installCmd, true);
                echo "  ✓ Repository dependencies installed\n";
            }
        }
        
        // Create build directory
        echo "  Setting up: Creating build directory...\n";
        $this->createDirectory($buildDir);
        echo "  ✓ Build directory ready\n";
        
        if ($treeSitterBin === null) {
            // System tree-sitter not found, install via npm
            echo "  Building: Installing npm dependencies (system tree-sitter not found)...\n";
            $this->executeCommand(
                "cd " . escapeshellarg($buildDir) . " && " .
                "npm init -y && " .
                "npm install tree-sitter-cli " . escapeshellarg($repoDir),
                true
            );
            echo "  ✓ Dependencies installed\n";
            $treeSitterBin = $buildDir . '/node_modules/.bin/tree-sitter';
        } else {
            echo "  Using system tree-sitter: {$treeSitterBin}\n";
        }
        
        // Build all grammars
        $builtLibraries = [];
        foreach ($grammarDirs as $grammarDir) {
            $grammarName = basename($grammarDir);
            if ($grammarDir === $repoDir) {
                $grammarName = $parser['language'];
            }
            
            echo "  Building grammar: {$grammarName}\n";
            
            // Generate parser for this grammar
            $this->executeCommand(
                "cd " . escapeshellarg($grammarDir) . " && " .
                escapeshellarg($treeSitterBin) . " generate",
                true
            );
            
            // Find and move parser.c to a unique location in build dir
            $parserC = null;
            $parserCandidates = [
                $grammarDir . '/parser.c',
                $grammarDir . '/src/parser.c'
            ];
            
            foreach ($parserCandidates as $candidate) {
                if (file_exists($candidate)) {
                    $parserC = $candidate;
                    break;
                }
            }
            
            if ($parserC === null) {
                throw new Exception("Failed to find parser.c for grammar in {$grammarDir}");
            }
            
            // Copy parser.c to build directory with unique name
            $buildParserC = $buildDir . '/parser_' . $grammarName . '.c';
            copy($parserC, $buildParserC);
            echo "    ✓ Found parser.c: {$grammarName}\n";
            
            // Compile to shared library with unique name
            $libName = 'parser_' . $grammarName . '.so';
            $libPath = $buildDir . '/' . $libName;
            $this->executeCommand(
                "cd " . escapeshellarg($buildDir) . " && " .
                "gcc -shared -fPIC -I/usr/include/tree-sitter " .
                "-o " . escapeshellarg($libName) . " " . escapeshellarg(basename($buildParserC)),
                true
            );
            echo "    ✓ Compiled: {$libName}\n";
            
            $builtLibraries[] = [
                'name' => $grammarName,
                'so' => $libPath,
                'basename' => $libName
            ];
        }
        
        if (empty($builtLibraries)) {
            throw new Exception("No grammars were successfully built");
        }
        
        echo "  ✓ Built " . count($builtLibraries) . " grammar(s)\n";
        
        // Get tree-sitter version for package versioning (use tag version if available)
        $treeSitterBin = $this->findTreeSitterBinary();
        if ($packageVersion === null) {
            $packageVersion = $this->getTreeSitterVersion() ?: '0.1.0';
        }
        
        // Check for existing package.json or create one
        if (!file_exists($repoDir . '/package.json')) {
            $this->createPackageJson($repoDir, $parser, $packageVersion);
        }
        
        // Create build directory
        echo "  Setting up: Creating build directory...\n";
        $this->createDirectory($buildDir);
        echo "  ✓ Build directory ready\n";
        
        if ($treeSitterBin === null) {
            // System tree-sitter not found, install via npm
            echo "  Building: Installing npm dependencies (system tree-sitter not found)...\n";
            $this->executeCommand(
                "cd " . escapeshellarg($buildDir) . " && " .
                "npm init -y && " .
                "npm install tree-sitter-cli " . escapeshellarg($repoDir),
                true
            );
            echo "  ✓ Dependencies installed\n";
            $treeSitterBin = $buildDir . '/node_modules/.bin/tree-sitter';
        } else {
            echo "  Using system tree-sitter: {$treeSitterBin}\n";
            // No need to install anything - we just need grammar.js which is in the repo
        }
        
        // Create Debian package structure (pass built libraries info)
        echo "  Packaging: Creating Debian package structure...\n";
        $this->createDebianPackage($parser, $repoDir, $buildDir, $packageVersion, $builtLibraries);
        echo "  ✓ Debian structure created\n";
        
        // Build the package
        $packageFiles = $this->buildDebianPackage($parser, $repoDir, $currentCommit);
        
        return [
            'success' => true,
            'package_files' => $packageFiles,
            'build_dir' => $buildDir,
            'repo_dir' => $repoDir
        ];
    }
    
    /**
     * Create package.json if missing
     */
    private function createPackageJson(string $repoDir, array $parser, string $version): void {
        $packageJson = [
            'name' => $parser['name'],
            'version' => $version,
            'description' => 'Tree-sitter parser for ' . $parser['language'] . ' language',
            'main' => 'index.js',
            'scripts' => [
                'build' => 'tree-sitter generate && tree-sitter build'
            ],
            'dependencies' => [
                'tree-sitter-cli' => '^0.20.0'
            ],
            'keywords' => ['parser', 'tree-sitter', $parser['language']],
            'author' => 'Various Contributors',
            'license' => 'MIT'
        ];
        
        file_put_contents(
            $repoDir . '/package.json',
            json_encode($packageJson, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)
        );
    }
    
    /**
     * Create Debian package structure
     */
    private function createDebianPackage(array $parser, string $repoDir, string $buildDir, string $version, array $builtLibraries = []): void {
        $debianDir = $repoDir . '/debian';
        $this->createDirectory($debianDir);
        $this->createDirectory($debianDir . '/source');
        
        // 1. Create debian/control
        $controlContent = $this->generateControlFile($parser, $builtLibraries);
        file_put_contents($debianDir . '/control', $controlContent);
        
        // 2. Create debian/rules
        $rulesContent = $this->generateRulesFile($parser, $builtLibraries);
        file_put_contents($debianDir . '/rules', $rulesContent);
        chmod($debianDir . '/rules', 0755);
        
        // 3. Create debian/changelog
        $changelogContent = $this->generateChangelog($parser, $version);
        file_put_contents($debianDir . '/changelog', $changelogContent);
        
        // 4. Create debian/copyright
        $copyrightContent = $this->generateCopyright($parser);
        file_put_contents($debianDir . '/copyright', $copyrightContent);
        
        // 5. Remove debian/compat if it exists (we use debhelper-compat in control instead)
        $compatFile = $debianDir . '/compat';
        if (file_exists($compatFile)) {
            unlink($compatFile);
        }
        
        // 6. Create debian/source/format
        file_put_contents($debianDir . '/source/format', "3.0 (quilt)\n");
        
        // 7. Create debian/install - include all built libraries
        $installContent = "";
        if (empty($builtLibraries)) {
            // Fallback: use language name to ensure unique .so filename
            // This should never happen if buildPackage works correctly, but just in case
            $fallbackName = 'parser_' . $parser['language'] . '.so';
            $installContent = "build/{$fallbackName} usr/lib/x86_64-linux-gnu/\n";
        } else {
            // Install all built libraries (each with unique name: parser_<language>.so or parser_<grammar>.so)
            foreach ($builtLibraries as $lib) {
                $installContent .= "build/" . $lib['basename'] . " usr/lib/x86_64-linux-gnu/\n";
            }
        }
        file_put_contents($debianDir . '/install', $installContent);
        
        // Note: No pkg-config file or headers needed - only runtime library is packaged
    }
    
    private function generateControlFile(array $parser, array $builtLibraries = []): string {
        $languageName = ucfirst($parser['language']);
        $packageName = $parser['name'];
        
        // Build description with grammar list if multiple
        $description = "Tree-sitter parser for {$languageName} language (runtime library)";
        $grammarList = "";
        if (count($builtLibraries) > 1) {
            $grammarNames = array_map(function($lib) { return $lib['name']; }, $builtLibraries);
            $description = "Tree-sitter parsers for {$languageName} (runtime libraries)";
            $grammarList = " This package includes parsers for: " . implode(', ', $grammarNames) . ".\n .";
        }
        
        return <<<CONTROL
Source: {$packageName}
Section: devel
Priority: optional
Maintainer: Auto Builder <builder@localhost>
Build-Depends: debhelper-compat (= 13), libtree-sitter-dev, nodejs (>= 14), npm, gcc, libc6-dev
Standards-Version: 4.6.1
Homepage: {$parser['repo']}
Rules-Requires-Root: no

Package: lib{$packageName}
Architecture: amd64
Multi-Arch: foreign
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: {$description}
 Tree-sitter is a parser generator tool and an incremental parsing library.
 This package contains the runtime shared libraries for {$languageName} language parsing.{$grammarList}
 .
 It can be used for syntax highlighting, code analysis, and other
 language tooling applications.
 .
 This package provides only the runtime libraries. For development, use
 libtree-sitter-dev which provides the main Tree-sitter API.
CONTROL;
    }
    
    private function generateRulesFile(array $parser, array $builtLibraries = []): string {
        $packageName = $parser['name'];
        $languageName = $parser['language'];
        
        // Build rules - simplified approach that works for both single and multi-grammar
        // We'll use a simpler script that finds and builds all grammars
        // In Makefiles, each line is a separate shell command, so we need proper continuation
        $buildRules = <<<BUILDRULES
	set -e; \
	if command -v tree-sitter >/dev/null 2>&1; then \
		TS_BIN=tree-sitter; \
	else \
		cd build && npm init -y >/dev/null 2>&1 && npm install tree-sitter-cli ../ >/dev/null 2>&1; \
		TS_BIN="npx tree-sitter"; \
	fi; \
	cd build; \
	if [ -f ../grammar.js ]; then \
		cd .. && \$\$TS_BIN generate >/dev/null 2>&1; \
		if [ -f src/parser.c ]; then cp src/parser.c build/parser_{$languageName}.c; \
		elif [ -f parser.c ]; then cp parser.c build/parser_{$languageName}.c; fi; \
		if [ -f src/scanner.c ]; then cp src/scanner.c build/scanner_{$languageName}.c; \
		elif [ -f scanner.c ]; then cp scanner.c build/scanner_{$languageName}.c; fi; \
		cd build; \
	fi; \
	for subdir in ../*/grammar.js; do \
		if [ -f "\$\$subdir" ]; then \
			grammar_name=\$\$(basename \$\$(dirname "\$\$subdir")); \
			cd \$\$(dirname "\$\$subdir") && \$\$TS_BIN generate >/dev/null 2>&1; \
			if [ -f src/parser.c ]; then cp src/parser.c ../build/parser_\$\$grammar_name.c; \
			elif [ -f parser.c ]; then cp parser.c ../build/parser_\$\$grammar_name.c; fi; \
			if [ -f src/scanner.c ]; then cp src/scanner.c ../build/scanner_\$\$grammar_name.c; \
			elif [ -f scanner.c ]; then cp scanner.c ../build/scanner_\$\$grammar_name.c; fi; \
			cd ../build; \
		fi; \
	done; \
	for parser_c in parser*.c; do \
		if [ -f "\$\$parser_c" ]; then \
			so_name=\$\$(echo "\$\$parser_c" | sed 's/\.c\$\$/.so/'); \
			lang_name=\$\$(echo "\$\$parser_c" | sed 's/parser_//; s/\.c\$\$//'); \
			scanner_c=""; \
			if [ -f scanner_\$\$lang_name.c ]; then \
				scanner_c="scanner_\$\$lang_name.c"; \
			fi; \
			if [ -n "\$\$scanner_c" ]; then \
				gcc -shared -fPIC -I/usr/include/tree-sitter -o "\$\$so_name" "\$\$parser_c" "\$\$scanner_c" -ltree-sitter >/dev/null 2>&1 || true; \
			else \
				gcc -shared -fPIC -I/usr/include/tree-sitter -o "\$\$so_name" "\$\$parser_c" -ltree-sitter >/dev/null 2>&1 || true; \
			fi; \
		fi; \
	done
BUILDRULES;
        
        return <<<RULES
#!/usr/bin/make -f
%:
	dh \$@ --builddirectory=build

override_dh_auto_clean:
	rm -rf build
	# Don't call dh_auto_clean - it tries to auto-detect build systems and fails

override_dh_auto_configure:
	mkdir -p build

override_dh_auto_build:
{$buildRules}

override_dh_auto_test:
	# Skip auto-test detection to avoid python-distutils errors
	true

override_dh_auto_install:
	# Install all shared libraries (runtime only - no dev package needed)
	install -d debian/lib{$packageName}/usr/lib/x86_64-linux-gnu/
	install -m 755 build/*.so debian/lib{$packageName}/usr/lib/x86_64-linux-gnu/

override_dh_missing:
	dh_missing --fail-missing

override_dh_shlibdeps:
	dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info
RULES;
    }
    
    private function generateChangelog(array $parser, string $version): string {
        $date = date('r');
        
        return <<<CHANGELOG
{$parser['name']} ({$version}-1) unstable; urgency=medium

  * Initial automated build
  * Tree-sitter parser for {$parser['language']}

 -- Auto Builder <builder@localhost>  {$date}
CHANGELOG;
    }
    
    private function generateCopyright(array $parser): string {
        return <<<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: {$parser['name']}
Source: {$parser['repo']}

Files: *
Copyright: Various contributors
License: MIT

Files: debian/*
Copyright: 2024 Auto Builder
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
COPYRIGHT;
    }
    
    private function generatePkgConfig(array $parser, string $version): string {
        $packageName = $parser['name'];
        
        return <<<PKGCONFIG
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib/x86_64-linux-gnu
includedir=\${prefix}/include

Name: {$packageName}
Description: Tree-sitter parser for {$parser['language']} language
Version: {$version}
Libs: -L\${libdir} -l{$parser['language']}
Cflags: -I\${includedir}/tree_sitter
PKGCONFIG;
    }
    
    /**
     * Build Debian package using dpkg-buildpackage
     */
    private function buildDebianPackage(array $parser, string $repoDir, string $currentCommit): array {
        $packageFiles = [];
        
        // Build the package
        echo "  Building: Creating Debian package...\n";
        $this->executeCommand(
            "cd " . escapeshellarg($repoDir) . " && " .
            "dpkg-buildpackage -us -uc -b",
            true
        );
        echo "  ✓ Debian package built\n";
        
        // Find and move package files
        // Package names have 'lib' prefix: libtree-sitter-vala-*.deb
        $parentDir = dirname($repoDir);
        $packageName = 'lib' . $parser['name'];
        $pattern = $parentDir . '/' . $packageName . '_*.deb';
        
        foreach (glob($pattern) as $debFile) {
            // Rename to use hyphen before version: libtree-sitter-bash-0.20.5-1_amd64.deb
            $basename = basename($debFile);
            // Replace first underscore with hyphen: libtree-sitter-bash_0.20.5-1_amd64.deb -> libtree-sitter-bash-0.20.5-1_amd64.deb
            $newBasename = preg_replace('/^(.+?)_(.+)$/', '$1-$2', $basename);
            $targetFile = $this->baseDir . '/' . $newBasename;
            rename($debFile, $targetFile);
            $packageFiles[] = $targetFile;
            
            // Also move other package files (rename to match new format)
            $oldBaseName = preg_replace('/\.deb$/', '', $basename);
            $newBaseName = preg_replace('/\.deb$/', '', $newBasename);
            $relatedFiles = [
                '.changes',
                '.buildinfo',
                '.dsc',
                '.tar.xz',
                '.tar.gz'
            ];
            
            foreach ($relatedFiles as $ext) {
                $relatedFile = $parentDir . '/' . $oldBaseName . $ext;
                if (file_exists($relatedFile)) {
                    // Rename to match new format (hyphen before version)
                    $newRelatedName = preg_replace('/^(.+?)_(.+)$/', '$1-$2', basename($relatedFile));
                    $target = $this->baseDir . '/' . $newRelatedName;
                    rename($relatedFile, $target);
                }
            }
        }
        
        // Check if package files were created
        if (empty($packageFiles)) {
            throw new Exception("Build completed but no package files found in {$parentDir} matching pattern: {$pattern}");
        }
        
        // Save commit ID to track this build
        // Get the current commit ID again (in case it changed during build)
        $finalCommit = trim($this->executeCommand(
            "cd " . escapeshellarg($repoDir) . " && git rev-parse HEAD",
            false
        ));
        
        // Save commit file in the repository directory
        $commitFile = $repoDir . '/debian_package_commit.txt';
        echo "  Saving commit ID to: {$commitFile}\n";
        echo "    Commit: {$finalCommit}\n";
        echo "    Package files found: " . count($packageFiles) . "\n";
        
        // Save commit ID without newline for easier comparison
        $result = @file_put_contents($commitFile, $finalCommit);
        if ($result === false) {
            throw new Exception("Failed to save commit ID to {$commitFile}. Check permissions on repository directory: {$repoDir}");
        } else {
            echo "  ✓ Saved commit ID: {$finalCommit} to {$commitFile}\n";
            echo "    File size: " . filesize($commitFile) . " bytes\n";
            // Verify it was written correctly
            $verify = trim(file_get_contents($commitFile));
            if ($verify !== $finalCommit) {
                throw new Exception("Verification failed! Written: '{$verify}', Expected: '{$finalCommit}'");
            } else {
                echo "    Verified: Commit ID matches\n";
            }
        }
        
        return $packageFiles;
    }
    
    /**
     * Install built packages
     */
    private function installPackage(array $packageFiles): void {
        foreach ($packageFiles as $debFile) {
            if (file_exists($debFile)) {
                echo "  Installing: " . basename($debFile) . "\n";
                $this->executeCommand("sudo dpkg -i " . escapeshellarg($debFile));
            }
        }
    }
    
    /**
     * Show build summary
     */
    private function showSummary(float $duration): void {
        echo str_repeat('=', 60) . "\n";
        echo "BUILD SUMMARY\n";
        echo str_repeat('=', 60) . "\n\n";
        
        $success = 0;
        $failed = 0;
        
        foreach ($this->results as $key => $result) {
            $parser = $this->parsers[$key];
            $status = $result['success'] ? '✓' : '✗';
            $message = $result['success'] ? 
                (isset($result['skipped']) && $result['skipped'] ? 'Skipped (already built)' : 'Built successfully') : 
                'Failed: ' . ($result['error'] ?? 'Unknown error');
            
            echo sprintf("%-15s %-30s %s\n",
                $status,
                $parser['name'],
                $message
            );
            
            if ($result['success']) {
                $success++;
                
                if (!empty($result['package_files'])) {
                    foreach ($result['package_files'] as $file) {
                        echo "    → " . basename($file) . "\n";
                    }
                }
            } else {
                $failed++;
            }
        }
        
        echo "\n";
        echo "Success: {$success}\n";
        echo "Failed:  {$failed}\n";
        echo "Total:   " . count($this->parsers) . "\n";
        echo "Duration: " . round($duration, 2) . " seconds\n";
        echo "Packages saved to: {$this->baseDir}\n";
    }
    
    /**
     * Utility: Execute shell command
     */
    private function executeCommand(string $command, bool $verbose = false): string {
        $output = [];
        $returnCode = 0;
        
        if ($verbose) {
            echo "    Executing: {$command}\n";
        }
        
        exec($command . ' 2>&1', $output, $returnCode);
        
        if ($returnCode !== 0) {
            $errorOutput = implode("\n", $output);
            if ($verbose && !empty($errorOutput)) {
                echo "    Command output:\n";
                foreach ($output as $line) {
                    echo "      {$line}\n";
                }
            }
            throw new Exception(
                "Command failed with code {$returnCode}:\n" . 
                "Command: {$command}\n" .
                "Output:\n{$errorOutput}"
            );
        }
        
        if ($verbose && !empty($output)) {
            foreach ($output as $line) {
                if (trim($line) !== '') {
                    echo "    {$line}\n";
                }
            }
        }
        
        return implode("\n", $output);
    }
    
    /**
     * Utility: Create directory
     */
    private function createDirectory(string $path): void {
        if (!is_dir($path)) {
            mkdir($path, 0755, true);
        }
    }
    
    /**
     * Find tree-sitter binary - check system first, then npm
     */
    private function findTreeSitterBinary(): ?string {
        // Check for system tree-sitter
        exec("which tree-sitter 2>/dev/null", $output, $returnCode);
        if ($returnCode === 0 && !empty($output)) {
            $path = trim($output[0]);
            if (!empty($path) && file_exists($path)) {
                return $path;
            }
        }
        
        return null;
    }
    
    /**
     * Get tree-sitter version from system installation
     */
    private function getTreeSitterVersion(): ?string {
        $treeSitterBin = $this->findTreeSitterBinary();
        if ($treeSitterBin === null) {
            return null;
        }
        
        try {
            $versionOutput = $this->executeCommand(
                escapeshellarg($treeSitterBin) . " --version",
                false
            );
            // Parse version from output like "tree-sitter 0.20.8"
            if (preg_match('/tree-sitter\s+([\d.]+)/', $versionOutput, $matches)) {
                return $matches[1];
            }
        } catch (Exception $e) {
            // Version command failed, return null
        }
        
        return null;
    }
    
    /**
     * Find the best matching tag for a given version
     * Returns the highest tag version that is <= the target version
     */
    private function findMatchingTag(string $repoDir, string $targetVersion): ?string {
        // First try exact match with various formats
        $tagFormats = [
            'v' . $targetVersion,
            $targetVersion,
            'tree-sitter-' . $targetVersion
        ];
        
        foreach ($tagFormats as $tag) {
            exec("cd " . escapeshellarg($repoDir) . " && git rev-parse --verify --quiet refs/tags/" . escapeshellarg($tag) . " >/dev/null 2>&1", $output, $returnCode);
            if ($returnCode === 0) {
                return $tag;
            }
        }
        
        // No exact match, find the highest tag <= target version
        // Get all tags
        exec("cd " . escapeshellarg($repoDir) . " && git tag", $tags, $returnCode);
        if ($returnCode !== 0 || empty($tags)) {
            return null;
        }
        
        // Parse target version
        $targetParts = array_map('intval', explode('.', $targetVersion));
        
        $bestTag = null;
        $bestVersion = null;
        
        foreach ($tags as $tag) {
            // Try to extract version from tag (remove 'v' prefix, etc.)
            $tagVersion = preg_replace('/^v/i', '', $tag);
            $tagVersion = preg_replace('/^tree-sitter-/i', '', $tagVersion);
            
            // Check if it looks like a version number
            if (!preg_match('/^\d+\.\d+\.\d+/', $tagVersion)) {
                continue;
            }
            
            // Parse tag version
            $tagParts = array_map('intval', explode('.', $tagVersion));
            
            // Compare versions (must be <= target)
            if ($this->compareVersions($tagParts, $targetParts) <= 0) {
                // This tag is <= target, check if it's better than current best
                if ($bestVersion === null || $this->compareVersions($tagParts, $bestVersion) > 0) {
                    $bestTag = $tag;
                    $bestVersion = $tagParts;
                }
            }
        }
        
        return $bestTag;
    }
    
    /**
     * Compare two version arrays
     * Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
     */
    private function compareVersions(array $v1, array $v2): int {
        $maxLen = max(count($v1), count($v2));
        
        // Pad arrays to same length
        $v1 = array_pad($v1, $maxLen, 0);
        $v2 = array_pad($v2, $maxLen, 0);
        
        for ($i = 0; $i < $maxLen; $i++) {
            if ($v1[$i] < $v2[$i]) {
                return -1;
            } elseif ($v1[$i] > $v2[$i]) {
                return 1;
            }
        }
        
        return 0;
    }
    
    /**
     * Extract version number from a tag
     * Handles formats like: v0.20.4, 0.20.4, tree-sitter-0.20.4
     */
    private function extractVersionFromTag(string $tag): ?string {
        // Remove common prefixes
        $version = preg_replace('/^v/i', '', $tag);
        $version = preg_replace('/^tree-sitter-/i', '', $version);
        
        // Check if it looks like a version number (e.g., 0.20.4)
        if (preg_match('/^(\d+\.\d+\.\d+)/', $version, $matches)) {
            return $matches[1];
        }
        
        return null;
    }
    
    /**
     * Find directories containing grammar.js files (source grammars only, not generated grammar.json)
     * Returns array of directory paths (root first, then subdirectories)
     */
    private function findGrammarDirectories(string $repoDir): array {
        $grammarDirs = [];
        
        // Check root directory first
        // Only look for grammar.js (source), not grammar.json (generated)
        if (file_exists($repoDir . '/grammar.js')) {
            $grammarDirs[] = $repoDir;
        }
        
        // Check subdirectories for grammar.js files (source grammars)
        if (is_dir($repoDir)) {
            $dirs = scandir($repoDir);
            foreach ($dirs as $dir) {
                if ($dir === '.' || $dir === '..' || $dir === '.git' || $dir === 'node_modules' || $dir === 'src' || $dir === 'build') {
                    continue;
                }
                
                $subDir = $repoDir . '/' . $dir;
                if (is_dir($subDir)) {
                    // Only look for grammar.js (source), not grammar.json (generated)
                    if (file_exists($subDir . '/grammar.js')) {
                        $grammarDirs[] = $subDir;
                    }
                }
            }
        }
        
        return $grammarDirs;
    }
}

// Main execution
try {
    // Check for required dependencies using dpkg -l
    $requiredPackages = [
        'git',
        'nodejs',
        'npm',
        'build-essential',
        'devscripts',
        'debhelper',
        'libtree-sitter-dev',
        'libc6-dev',
        'tree-sitter-cli'
    ];
    
    $missingPackages = [];
    
    foreach ($requiredPackages as $package) {
        // Check if package is installed using dpkg-query (more reliable, handles :arch suffix)
        exec("dpkg-query -W " . escapeshellarg($package) . " >/dev/null 2>&1", $output, $returnCode);
        if ($returnCode !== 0) {
            $missingPackages[] = $package;
        }
    }
    
    if (!empty($missingPackages)) {
        echo "Error: Missing required packages.\n";
        echo "You should install these:\n";
        echo "sudo apt-get install " . implode(' ', $missingPackages) . "\n";
        exit(1);
    }
    
    // Check for optional tree-sitter (will use npm fallback if not found)
    exec("which tree-sitter 2>/dev/null", $output, $returnCode);
    if ($returnCode === 0) {
        echo "Info: Using system tree-sitter (will skip npm install for tree-sitter-cli)\n";
    } else {
        echo "Info: System tree-sitter not found, will install via npm\n";
    }
    
    // Run the builder
    $builder = new TreeSitterPackageBuilder();
    $builder->buildAll();
    
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(1);
}