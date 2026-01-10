#!/usr/bin/php
<?php
/**
 * Performance Test Script
 * 
 * This script runs "tell me a short story" on each available model
 * and collects performance data, then generates a summary report.
 * 
 * Usage: php perf_test.php
 */

class PerformanceTest {
    private string $cliPath;
    private string $perfDataDir;
    private string $summaryDir;
    private string $query;
    private array $models = [];
    private array $results = [];
    
    public function __construct() {
        // Get script directory and project root
        $scriptDir = dirname(__FILE__);
        $projectRoot = dirname(dirname($scriptDir));
        
        // Set paths
        $this->cliPath = $projectRoot . '/build/oc-test-cli';
        $this->perfDataDir = $projectRoot . '/build/perfdata';
        $this->summaryDir = $projectRoot . '/docs/perfdata';
        $this->query = 'tell me a short story';
        
        // Create directories if they don't exist
        $this->createDirectory($this->perfDataDir);
        $this->createDirectory($this->summaryDir);
        
        // Check if CLI exists
        if (!file_exists($this->cliPath)) {
            throw new Exception("CLI not found at: {$this->cliPath}\nPlease build the project first.");
        }
    }
    
    private function createDirectory(string $path): void {
        if (!is_dir($path)) {
            mkdir($path, 0755, true);
        }
    }
    
    private function sanitizeModelName(string $modelName): string {
        // Replace '/' with '_' for filename
        return str_replace('/', '_', $modelName);
    }
    
    private function listModels(): array {
        echo "Listing available models...\n";
        echo str_repeat('=', 60) . "\n";
        
        $command = escapeshellarg($this->cliPath) . ' --list-models 2>&1';
        $output = [];
        $returnCode = 0;
        
        exec($command, $output, $returnCode);
        
        if ($returnCode !== 0) {
            $error = implode("\n", $output);
            throw new Exception("Failed to list models:\n{$error}");
        }
        
        $models = [];
        foreach ($output as $line) {
            $line = trim($line);
            if (!empty($line)) {
                $models[] = $line;
            }
        }
        
        echo "Found " . count($models) . " model(s):\n";
        foreach ($models as $model) {
            echo "  - {$model}\n";
        }
        echo "\n";
        
        return $models;
    }
    
    private function runTest(string $model): bool {
        $sanitized = $this->sanitizeModelName($model);
        $statsFile = $this->perfDataDir . '/' . $sanitized . '.json';
        
        echo "\n" . str_repeat('=', 60) . "\n";
        echo "Testing model: {$model}\n";
        echo str_repeat('=', 60) . "\n";
        
        // Build command
        $queryEscaped = escapeshellarg($this->query);
        $modelEscaped = escapeshellarg($model);
        $statsFileEscaped = escapeshellarg($statsFile);
        
        $command = escapeshellarg($this->cliPath) . 
                   ' --model=' . $modelEscaped . 
                   ' --stats=' . $statsFileEscaped . 
                   ' ' . $queryEscaped . ' 2>&1';
        
        // Execute command with streaming output
        $descriptorspec = [
            0 => ['pipe', 'r'],  // stdin
            1 => ['pipe', 'w'],  // stdout
            2 => ['pipe', 'w']   // stderr
        ];
        
        $process = proc_open($command, $descriptorspec, $pipes);
        
        if (!is_resource($process)) {
            echo "ERROR: Failed to start process\n";
            return false;
        }
        
        // Close stdin
        fclose($pipes[0]);
        
        // Read output in real-time (streaming)
        $stdout = '';
        $stderr = '';
        $stdoutHandle = $pipes[1];
        $stderrHandle = $pipes[2];
        
        // Set streams to non-blocking
        stream_set_blocking($stdoutHandle, false);
        stream_set_blocking($stderrHandle, false);
        
        $stdoutClosed = false;
        $stderrClosed = false;
        
        while (true) {
            // Check if process is still running
            $status = proc_get_status($process);
            if (!$status['running']) {
                // Process ended, read any remaining data
                break;
            }
            
            // Build read array with only open streams
            $read = [];
            if (!$stdoutClosed) {
                $read[] = $stdoutHandle;
            }
            if (!$stderrClosed) {
                $read[] = $stderrHandle;
            }
            
            // If all streams are closed, break
            if (empty($read)) {
                break;
            }
            
            $write = null;
            $except = null;
            $changed = stream_select($read, $write, $except, 0, 200000); // 0.2 second timeout
            
            if ($changed === false) {
                // Error in select, check if process ended
                $status = proc_get_status($process);
                if (!$status['running']) {
                    break;
                }
                // Continue to retry
                continue;
            }
            
            // Read from stdout
            if (!$stdoutClosed && in_array($stdoutHandle, $read)) {
                $chunk = fread($stdoutHandle, 8192);
                if ($chunk === false || feof($stdoutHandle)) {
                    $stdoutClosed = true;
                } elseif ($chunk !== '') {
                    echo $chunk;
                    flush();
                    $stdout .= $chunk;
                }
            }
            
            // Read from stderr
            if (!$stderrClosed && in_array($stderrHandle, $read)) {
                $chunk = fread($stderrHandle, 8192);
                if ($chunk === false || feof($stderrHandle)) {
                    $stderrClosed = true;
                } elseif ($chunk !== '') {
                    echo $chunk;
                    flush();
                    $stderr .= $chunk;
                }
            }
            
            // If both streams are closed, check process status one more time
            if ($stdoutClosed && $stderrClosed) {
                $status = proc_get_status($process);
                if (!$status['running']) {
                    break;
                }
                // Wait a bit for process to finish
                usleep(100000); // 0.1 second
            }
        }
        
        // Read any remaining output (process has ended)
        if (!$stdoutClosed) {
            stream_set_blocking($stdoutHandle, true);
            $remainingStdout = stream_get_contents($stdoutHandle);
            if ($remainingStdout !== false && $remainingStdout !== '') {
                echo $remainingStdout;
                flush();
                $stdout .= $remainingStdout;
            }
        }
        
        if (!$stderrClosed) {
            stream_set_blocking($stderrHandle, true);
            $remainingStderr = stream_get_contents($stderrHandle);
            if ($remainingStderr !== false && $remainingStderr !== '') {
                echo $remainingStderr;
                flush();
                $stderr .= $remainingStderr;
            }
        }
        
        // Close pipes
        fclose($pipes[1]);
        fclose($pipes[2]);
        
        // Get exit code
        $returnCode = proc_close($process);
        
        // Check if stats file was created
        if (!file_exists($statsFile)) {
            echo "\nERROR: Stats file was not created: {$statsFile}\n";
            return false;
        }
        
        echo "\n✓ Stats saved to: {$statsFile}\n";
        
        return $returnCode === 0;
    }
    
    private function loadResults(): void {
        echo "\n" . str_repeat('=', 60) . "\n";
        echo "Loading performance data...\n";
        echo str_repeat('=', 60) . "\n";
        
        $files = glob($this->perfDataDir . '/*.json');
        
        if (empty($files)) {
            echo "No performance data files found.\n";
            return;
        }
        
        foreach ($files as $file) {
            $content = file_get_contents($file);
            if ($content === false) {
                echo "Warning: Failed to read {$file}\n";
                continue;
            }
            
            $data = json_decode($content, true);
            if ($data === null) {
                echo "Warning: Invalid JSON in {$file}\n";
                continue;
            }
            
            // Extract model name from filename (remove .json extension and convert _ back to /)
            $basename = basename($file, '.json');
            $modelName = str_replace('_', '/', $basename);
            
            // Calculate computed values
            $totalDurationS = isset($data['total_duration']) ? $data['total_duration'] / 1e9 : 0;
            $evalDurationS = isset($data['eval_duration']) ? $data['eval_duration'] / 1e9 : 0;
            $tokensPerSecond = $evalDurationS > 0 && isset($data['eval_count']) 
                ? $data['eval_count'] / $evalDurationS 
                : 0;
            
            $this->results[] = [
                'model' => $modelName,
                'file' => $file,
                'data' => $data,
                'total_duration_s' => $totalDurationS,
                'eval_duration_s' => $evalDurationS,
                'tokens_per_second' => $tokensPerSecond,
                'prompt_eval_count' => $data['prompt_eval_count'] ?? 0,
                'eval_count' => $data['eval_count'] ?? 0,
                'load_duration' => isset($data['load_duration']) ? $data['load_duration'] / 1e9 : 0,
                'prompt_eval_duration' => isset($data['prompt_eval_duration']) ? $data['prompt_eval_duration'] / 1e9 : 0,
            ];
        }
        
        // Sort by tokens per second (descending)
        usort($this->results, function($a, $b) {
            return $b['tokens_per_second'] <=> $a['tokens_per_second'];
        });
        
        echo "Loaded " . count($this->results) . " result(s)\n";
    }
    
    private function generateSummary(): void {
        $summaryFile = $this->summaryDir . '/tell-me-a-short-story.md';
        
        echo "\n" . str_repeat('=', 60) . "\n";
        echo "Generating summary report...\n";
        echo str_repeat('=', 60) . "\n";
        
        $markdown = "# Performance Test: \"Tell me a short story\"\n\n";
        $markdown .= "Generated: " . date('Y-m-d H:i:s') . "\n\n";
        $markdown .= "## Summary\n\n";
        $markdown .= "Total models tested: " . count($this->results) . "\n\n";
        
        if (empty($this->results)) {
            $markdown .= "No performance data available.\n";
            file_put_contents($summaryFile, $markdown);
            echo "Summary written to: {$summaryFile}\n";
            return;
        }
        
        // Calculate statistics
        $tokensPerSecond = array_column($this->results, 'tokens_per_second');
        $totalDurations = array_column($this->results, 'total_duration_s');
        $evalDurations = array_column($this->results, 'eval_duration_s');
        
        $markdown .= "### Overall Statistics\n\n";
        $markdown .= "- **Average tokens/second**: " . number_format(array_sum($tokensPerSecond) / count($tokensPerSecond), 2) . "\n";
        $markdown .= "- **Max tokens/second**: " . number_format(max($tokensPerSecond), 2) . "\n";
        $markdown .= "- **Min tokens/second**: " . number_format(min($tokensPerSecond), 2) . "\n";
        $markdown .= "- **Average total duration**: " . number_format(array_sum($totalDurations) / count($totalDurations), 2) . "s\n";
        $markdown .= "- **Average eval duration**: " . number_format(array_sum($evalDurations) / count($evalDurations), 2) . "s\n\n";
        
        // Detailed results table
        $markdown .= "## Detailed Results\n\n";
        $markdown .= "| Model | Tokens/s | Total Duration | Eval Duration | Tokens In | Tokens Out | Load Time | Prompt Eval Time |\n";
        $markdown .= "|-------|----------|----------------|---------------|-----------|------------|-----------|------------------|\n";
        
        foreach ($this->results as $result) {
            $model = $result['model'];
            $tps = number_format($result['tokens_per_second'], 2);
            $totalDur = number_format($result['total_duration_s'], 2) . 's';
            $evalDur = number_format($result['eval_duration_s'], 2) . 's';
            $promptCount = $result['prompt_eval_count'];
            $evalCount = $result['eval_count'];
            $loadDur = number_format($result['load_duration'], 3) . 's';
            $promptEvalDur = number_format($result['prompt_eval_duration'], 3) . 's';
            
            $markdown .= "| {$model} | {$tps} | {$totalDur} | {$evalDur} | {$promptCount} | {$evalCount} | {$loadDur} | {$promptEvalDur} |\n";
        }
        
        $markdown .= "\n## Performance Data Files\n\n";
        $markdown .= "All performance data is stored in JSON format in `build/perfdata/`:\n\n";
        
        foreach ($this->results as $result) {
            $basename = basename($result['file']);
            $markdown .= "- `{$basename}` - {$result['model']}\n";
        }
        
        file_put_contents($summaryFile, $markdown);
        echo "Summary written to: {$summaryFile}\n";
    }
    
    public function run(): void {
        echo "Performance Test Script\n";
        echo str_repeat('=', 60) . "\n\n";
        
        try {
            // Step 1: List models
            $this->models = $this->listModels();
            
            if (empty($this->models)) {
                echo "No models found. Exiting.\n";
                return;
            }
            
            // Step 2: Run tests on each model
            $successCount = 0;
            $failCount = 0;
            
            foreach ($this->models as $model) {
                if ($this->runTest($model)) {
                    $successCount++;
                } else {
                    $failCount++;
                }
            }
            
            echo "\n" . str_repeat('=', 60) . "\n";
            echo "Test Summary\n";
            echo str_repeat('=', 60) . "\n";
            echo "Successful: {$successCount}\n";
            echo "Failed: {$failCount}\n";
            echo "Total: " . count($this->models) . "\n";
            
            // Step 3: Load results and generate summary
            $this->loadResults();
            $this->generateSummary();
            
            echo "\n" . str_repeat('=', 60) . "\n";
            echo "Performance test completed!\n";
            echo str_repeat('=', 60) . "\n";
            
        } catch (Exception $e) {
            echo "\nERROR: " . $e->getMessage() . "\n";
            exit(1);
        }
    }
}

// Main execution
try {
    $test = new PerformanceTest();
    $test->run();
} catch (Exception $e) {
    echo "Fatal error: " . $e->getMessage() . "\n";
    exit(1);
}
