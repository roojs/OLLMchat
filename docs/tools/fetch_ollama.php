#!/usr/bin/php
<?php
/**
 * Ollama Model Data Scraper
 * 
 * This script scrapes Ollama's website to build a comprehensive model database.
 * It fetches search pages and model detail pages, then generates a JSON file
 * with model information including features, tags, sizes, and context windows.
 * 
 * Usage: 
 *   php fetch_ollama.php
 *   php fetch_ollama.php --debug-derivative <model-name>
 *   php fetch_ollama.php --debug-tags <model-slug>
 */

class OllamaModelScraper {
    
    private string $baseDir;
    private string $cacheDir;
    private string $modelsDir;
    private string $outputFile;
    private array $models = [];
    private array $originalModels = []; // Models from original URL
    private array $derivativeModels = []; // Track which models are derivatives (by slug)
    private int $fetchedCount = 0;
    private int $popularCount = 0; // Models from popular page
    private int $newestCount = 0;  // Models from newest page
    private const MAX_FETCH_PER_RUN = 10;
    private const CACHE_AGE_HOURS = 24;
    private const ORIGINAL_URL = 'https://ollama-models.zwz.workers.dev/';
    
    public function __construct() {
        $homeDir = $_SERVER['HOME'] ?? getenv('HOME');
        if (empty($homeDir)) {
            throw new Exception("Cannot determine home directory");
        }
        
        $this->baseDir = $homeDir . '/.local/share/ollmchat';
        $this->cacheDir = $this->baseDir . '/fetch_ollama';
        $this->modelsDir = $this->cacheDir . '/models';
        
        // Output to resources directory (relative to script location: docs/tools/)
        $scriptDir = dirname(__FILE__);
        $projectRoot = dirname(dirname($scriptDir));
        $this->outputFile = $projectRoot . '/resources/ollama-models.json';
        
        // Create directories
        $this->createDirectory($this->cacheDir);
        $this->createDirectory($this->modelsDir);
        
        // Suppress HTML parsing warnings
        libxml_use_internal_errors(true);
    }
    
    private function createDirectory(string $path): void {
        if (!is_dir($path)) {
            mkdir($path, 0755, true);
        }
    }
    
    private function printStatusReport(): void {
        $totalModels = count($this->models);
        $baseModels = 0;
        $derivatives = 0;
        $fetched = 0;
        $needsFetching = 0;
        
        foreach ($this->models as $slug => $model) {
            // Check if it's a derivative
            if (isset($this->derivativeModels[$slug])) {
                $derivatives++;
            } else {
                $baseModels++;
            }
            
            // Check if HTML file exists (has been fetched)
            $fileSlug = str_replace('/', '_', $slug);
            $modelFile = $this->modelsDir . '/' . $fileSlug . '.html';
            
            if (file_exists($modelFile)) {
                $fetched++;
            } else {
                $needsFetching++;
            }
        }
        
        $totalOriginal = count($this->originalModels);
        $progress = $totalModels > 0 ? round(($fetched / $totalModels) * 100, 1) : 0;
        
        echo "\n" . str_repeat('=', 60) . "\n";
        echo "STATUS REPORT\n";
        echo str_repeat('=', 60) . "\n";
        echo "Original source models:     " . str_pad(number_format($totalOriginal), 10) . "\n";
        echo "Total discovered models:     " . str_pad(number_format($totalModels), 10) . "\n";
        echo "  ├─ Base models:            " . str_pad(number_format($baseModels), 10) . "\n";
        echo "  └─ Derivatives:            " . str_pad(number_format($derivatives), 10) . "\n";
        echo "\n";
        echo "Fetch status:\n";
        echo "  ├─ Fetched (have HTML):    " . str_pad(number_format($fetched), 10) . " (" . $progress . "%)\n";
        echo "  └─ Needs fetching:         " . str_pad(number_format($needsFetching), 10) . "\n";
        echo "\n";
        echo "Models with tags:           " . str_pad(number_format($this->countModelsWithTags()), 10) . "\n";
        echo str_repeat('=', 60) . "\n\n";
    }
    
    private function countModelsWithTags(): int {
        $count = 0;
        foreach ($this->models as $model) {
            if (!empty($model['tags'])) {
                $count++;
            }
        }
        return $count;
    }
    
    private function shouldFetch(string $filePath, int $maxAgeHours = self::CACHE_AGE_HOURS): bool {
        if (!file_exists($filePath)) {
            return true;
        }
        
        $fileTime = filemtime($filePath);
        $ageHours = (time() - $fileTime) / 3600;
        
        return $ageHours >= $maxAgeHours;
    }
    
    private function fetchUrl(string $url, string $outputPath, bool $checkAge = true): bool {
        if ($checkAge && !$this->shouldFetch($outputPath)) {
            return true;
        }
        
        echo "  Fetching: {$url}\n";
        
        try {
            $context = stream_context_create([
                'http' => [
                    'method' => 'GET',
                    'header' => [
                        'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                    ],
                    'timeout' => 30,
                    'ignore_errors' => true
                ]
            ]);
            
            // Use wrapper_data to get response headers
            $content = @file_get_contents($url, false, $context);
            
            // Get HTTP response code from wrapper_data
            $httpResponseCode = null;
            if (isset($http_response_header)) {
                if (preg_match('/HTTP\/\d\.\d\s+(\d+)/', $http_response_header[0], $matches)) {
                    $httpResponseCode = (int)$matches[1];
                }
            }
            
            if ($content === false) {
                $error = error_get_last();
                $errorMsg = $error !== null ? $error['message'] : 'Unknown error';
                echo "  Error: Failed to fetch {$url}\n";
                echo "    HTTP Code: " . ($httpResponseCode ?? 'unknown') . "\n";
                echo "    Error: {$errorMsg}\n";
                
                // Check for rate limiting
                if ($httpResponseCode === 429 || $httpResponseCode === 503) {
                    echo "\n  *** RATE LIMITING DETECTED (HTTP {$httpResponseCode}) ***\n";
                    echo "  Stopping fetch operations. Please wait before retrying.\n\n";
                    throw new Exception("Rate limited - HTTP {$httpResponseCode}");
                }
                
                return false;
            }
            
            if (empty($content)) {
                echo "  Warning: Empty response from {$url}\n";
                echo "    HTTP Code: " . ($httpResponseCode ?? 'unknown') . "\n";
                return false;
            }
            
            // Check HTTP response code first
            if ($httpResponseCode !== null) {
                if ($httpResponseCode === 404) {
                    echo "  *** 404 NOT FOUND ***\n";
                    echo "    URL: {$url}\n";
                    echo "    This model may not exist or the URL is incorrect.\n";
                    echo "    Stopping fetch operations to investigate.\n\n";
                    throw new Exception("404 Not Found for URL: {$url}");
                }
                
                if ($httpResponseCode === 429 || $httpResponseCode === 503) {
                    echo "\n  *** RATE LIMITING DETECTED (HTTP {$httpResponseCode}) ***\n";
                    echo "  Stopping fetch operations. Please wait before retrying.\n\n";
                    throw new Exception("Rate limited - HTTP {$httpResponseCode}");
                }
                
                if ($httpResponseCode >= 400) {
                    echo "  Warning: HTTP {$httpResponseCode} response from {$url}\n";
                    echo "    Response preview: " . substr(strip_tags($content), 0, 100) . "...\n";
                }
            }
            
            // Check if response is a 404 page (even if HTTP code wasn't captured)
            if (strpos($content, '404.') !== false && strpos($content, "That's an error") !== false) {
                echo "  *** 404 PAGE DETECTED IN CONTENT ***\n";
                echo "    URL: {$url}\n";
                echo "    HTTP Code: " . ($httpResponseCode ?? 'unknown') . "\n";
                echo "    This model may not exist or the URL is incorrect.\n";
                echo "    Stopping fetch operations to investigate.\n\n";
                throw new Exception("404 page detected for URL: {$url}");
            }
            
            // Check for rate limiting in content
            if (stripos($content, 'rate limit') !== false || stripos($content, 'too many requests') !== false) {
                echo "\n  *** RATE LIMITING DETECTED IN RESPONSE ***\n";
                echo "  Stopping fetch operations. Please wait before retrying.\n\n";
                throw new Exception("Rate limiting detected in response");
            }
            
            // Ensure directory exists
            $dir = dirname($outputPath);
            if (!is_dir($dir)) {
                $this->createDirectory($dir);
            }
            
            if (file_put_contents($outputPath, $content) === false) {
                echo "  Error: Failed to write to {$outputPath}\n";
                return false;
            }
            
            echo "  Saved: " . basename($outputPath);
            if ($httpResponseCode !== null) {
                echo " (HTTP {$httpResponseCode})";
            }
            echo "\n";
            return true;
            
        } catch (Exception $e) {
            // Re-throw if it's our custom exception (404, rate limit)
            if (strpos($e->getMessage(), '404') !== false || strpos($e->getMessage(), 'Rate') !== false) {
                throw $e;
            }
            echo "  Error: Exception while fetching {$url}: " . $e->getMessage() . "\n";
            return false;
        }
    }
    
    public function run(): void {
        // Check for debug mode
        global $argv;
        $debugModel = null;
        $debugTags = null;
        foreach ($argv as $i => $arg) {
            if ($arg === '--debug-derivative' && isset($argv[$i + 1])) {
                $debugModel = $argv[$i + 1];
                break;
            }
            if ($arg === '--debug-tags' && isset($argv[$i + 1])) {
                $debugTags = $argv[$i + 1];
                break;
            }
        }
        
        if ($debugModel !== null) {
            // For debug mode, we need to load models first
            try {
                // Step 0: Fetch original model data (needed to find the model)
                $this->fetchOriginalModels();
                
                // Step 1-2: Fetch and parse search results (needed to populate models array)
                $this->fetchSearchPages();
                $this->parseSearchResults();
                
                // Now run debug
                $this->debugDerivativeSearch($debugModel);
            } catch (Exception $e) {
                echo "\nError: " . $e->getMessage() . "\n";
                exit(1);
            }
            return;
        }
        
        if ($debugTags !== null) {
            // Debug tag extraction for a specific model
            try {
                $this->debugTagExtraction($debugTags);
            } catch (Exception $e) {
                echo "\nError: " . $e->getMessage() . "\n";
                exit(1);
            }
            return;
        }
        
        echo "Ollama Model Scraper\n";
        echo str_repeat('=', 60) . "\n\n";
        
        try {
            // Step 0: Fetch original model data
            $this->fetchOriginalModels();
            
            // Step 1: Fetch search pages
            $this->fetchSearchPages();
            
            // Step 2: Parse search results
            $this->parseSearchResults();
            
            // Show status after discovering models
            $this->printStatusReport();
            
            // Step 3: Fetch model detail pages
            $this->fetchModelDetails();
            
            // Step 4: Parse model detail pages
            $this->parseModelDetails();
            
            // Step 5: Fetch derivative models for top 5 popular models
            $this->fetchDerivativeModels();
            
            // Step 5b: Fetch any remaining derivative models that were discovered but not yet fetched
            // (This handles derivatives that were added to the array but not fetched due to limits)
            $this->fetchModelDetails(false);
            
            // Show status after fetching derivatives
            $this->printStatusReport();
            
            // Step 6: Parse any newly fetched derivative models
            $this->parseModelDetails();
            
            // Step 7: Merge data and generate JSON output
            $stats = $this->mergeAndGenerateJson();
            
            // Calculate completion statistics
            $totalOriginal = count($this->originalModels);
            $totalUnique = $stats['total_unique'];
            $modelsWithTags = $stats['with_tags'];
            $percentage = $totalUnique > 0 ? round(($modelsWithTags / $totalUnique) * 100, 1) : 0;
            
            // Final status report
            $this->printStatusReport();
            
            echo "Completed successfully!\n";
            echo "Total models from original source: {$totalOriginal}\n";
            echo "Total unique models (after merging): {$totalUnique}\n";
            echo "Models from popular page: {$this->popularCount}\n";
            echo "Models from newest page: {$this->newestCount}\n";
            echo "Models with tags (in output): {$modelsWithTags}\n";
            echo "Completion: {$percentage}%\n";
            echo "Output: {$this->outputFile}\n";
            
        } catch (Exception $e) {
            echo "\nError: " . $e->getMessage() . "\n";
            exit(1);
        }
    }
    
    private function fetchOriginalModels(): void {
        echo "Step 0: Fetching original model data...\n";
        
        $cacheFile = $this->cacheDir . '/original-models.json';
        
        // Check if we should fetch (24 hour cache)
        if ($this->shouldFetch($cacheFile)) {
            $context = stream_context_create([
                'http' => [
                    'method' => 'GET',
                    'header' => [
                        'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                    ],
                    'timeout' => 30,
                    'ignore_errors' => true
                ]
            ]);
            
            echo "  Fetching from: " . self::ORIGINAL_URL . "\n";
            $json = @file_get_contents(self::ORIGINAL_URL, false, $context);
            
            if ($json === false) {
                echo "  Warning: Failed to fetch original model data\n";
                // Try to load from cache if available
                if (file_exists($cacheFile)) {
                    echo "  Loading from cache instead\n";
                    $json = file_get_contents($cacheFile);
                } else {
                    return;
                }
            } else {
                // Save to cache
                file_put_contents($cacheFile, $json);
                echo "  Saved to cache\n";
            }
        } else {
            echo "  Loading from cache (cache is fresh)\n";
            $json = file_get_contents($cacheFile);
        }
        
        $data = json_decode($json, true);
        
        if ($data === null || !is_array($data)) {
            echo "  Warning: Invalid JSON from original URL\n";
            return;
        }
        
        // Index by model name for easy lookup
        foreach ($data as $model) {
            if (isset($model['name'])) {
                $this->originalModels[$model['name']] = $model;
            }
        }
        
        echo "  Loaded " . count($this->originalModels) . " models from original source\n\n";
    }
    
    private function fetchSearchPages(): void {
        echo "Step 1: Fetching search pages...\n";
        
        $popularUrl = 'https://ollama.com/search';
        $popularFile = $this->cacheDir . '/popular.html';
        
        $newestUrl = 'https://ollama.com/search?o=newest';
        $newestFile = $this->cacheDir . '/newest.html';
        
        $this->fetchUrl($popularUrl, $popularFile);
        $this->fetchUrl($newestUrl, $newestFile);
        
        echo "\n";
    }
    
    private function parseSearchResults(): void {
        echo "Step 2: Parsing search results...\n";
        
        $files = [
            ['file' => $this->cacheDir . '/popular.html', 'source' => 'popular'],
            ['file' => $this->cacheDir . '/newest.html', 'source' => 'newest']
        ];
        
        $foundModels = [];
        
        foreach ($files as $fileInfo) {
            $file = $fileInfo['file'];
            $source = $fileInfo['source'];
            if (!file_exists($file)) {
                echo "  Warning: File not found: " . basename($file) . "\n";
                continue;
            }
            
            $dom = new DOMDocument();
            $oldErrors = libxml_use_internal_errors(true);
            
            $loaded = @$dom->loadHTMLFile($file);
            
            if ($loaded === false) {
                $errors = libxml_get_errors();
                libxml_clear_errors();
                libxml_use_internal_errors($oldErrors);
                echo "  Error: Failed to parse HTML";
                if (!empty($errors)) {
                    echo " - " . $errors[0]->message;
                }
                echo "\n";
                continue;
            }
            
            libxml_clear_errors();
            libxml_use_internal_errors($oldErrors);
            
            $xpath = new DOMXPath($dom);
            
            // Find all model list items
            // The structure is: //*[@id="searchresults"]/ul/li
            $listItems = $xpath->query('//*[@id="searchresults"]/ul/li');
            
            if ($listItems === false || $listItems->length === 0) {
                echo "  Warning: No search results found\n";
                continue;
            }
            
            foreach ($listItems as $index => $li) {
                // Get the anchor tag
                $anchor = $xpath->query('.//a', $li)->item(0);
                if ($anchor === null) {
                    continue;
                }
                
                // Extract model slug from href (e.g., /library/gpt-oss -> gpt-oss, /library/huihui_ai/gemma3-abliterated -> huihui_ai/gemma3-abliterated)
                $href = $anchor->getAttribute('href');
                if (!preg_match('#/library/(.+?)(?:/tags|$)#', $href, $matches)) {
                    continue;
                }
                $modelSlug = $matches[1];
                
                // Track if this is a new model (not seen before)
                $isNew = !isset($foundModels[$modelSlug]);
                
                // Extract model name from div[1]/h2/span (as per user's XPath example)
                $nameNode = $xpath->query('.//div[1]/h2/span', $anchor)->item(0);
                if ($nameNode === null) {
                    // Fallback: try just h2/span
                    $nameNode = $xpath->query('.//h2/span', $anchor)->item(0);
                }
                $modelName = $nameNode !== null ? trim($nameNode->textContent) : $modelSlug;
                
                // Extract description from p tag (user mentioned it's the 9th item, but we'll look for p in the anchor)
                $descNode = $xpath->query('.//div[1]/p', $anchor)->item(0);
                if ($descNode === null) {
                    // Fallback: try any p tag
                    $descNode = $xpath->query('.//p', $anchor)->item(0);
                }
                $description = $descNode !== null ? trim($descNode->textContent) : '';
                
                // Count by source (count all models found on each page, even if duplicates)
                if ($source === 'popular') {
                    $this->popularCount++;
                } else {
                    $this->newestCount++;
                }
                
                // Only add to foundModels if it's new (for deduplication)
                if ($isNew) {
                    $foundModels[$modelSlug] = [
                        'name' => $modelName,
                        'slug' => $modelSlug,
                        'description' => $description,
                        'source' => $source
                    ];
                }
            }
        }
        
        // Convert to models array
        foreach ($foundModels as $slug => $data) {
            $this->models[$slug] = [
                'name' => $data['name'],
                'description' => $data['description'],
                'features' => [],
                'tags' => [],
                'downloads' => null
            ];
        }
        
        echo "  Found " . count($this->models) . " unique models\n\n";
    }
    
    private function fetchModelDetails(bool $resetCounter = true): void {
        if ($resetCounter) {
            echo "Step 3: Fetching model detail pages...\n";
            $this->fetchedCount = 0;
        } else {
            echo "Step 5b: Fetching remaining model detail pages...\n";
        }
        
        $initialCount = $this->fetchedCount;
        $skipped = 0;
        $isDerivative = false;
        
        foreach ($this->models as $slug => $model) {
            if ($this->fetchedCount >= self::MAX_FETCH_PER_RUN) {
                echo "  Reached limit of " . self::MAX_FETCH_PER_RUN . " fetches per run\n";
                break;
            }
            
            // Check if this is a derivative
            $isDerivative = isset($this->derivativeModels[$slug]);
            
            // Handle namespaced models (e.g., huihui_ai/gemma3-abliterated -> huihui_ai_gemma3-abliterated.html)
            $fileSlug = str_replace('/', '_', $slug);
            $modelFile = $this->modelsDir . '/' . $fileSlug . '.html';
            
            // Only fetch if file doesn't exist (one-time download)
            if (file_exists($modelFile)) {
                $skipped++;
                continue;
            }
            
            // Use /tags endpoint for full tag list
            // Derivatives (namespaced models) don't have /library/ in the URL
            // Base models: /library/model-name
            // Derivatives: /author/model-name
            if (strpos($slug, '/') !== false) {
                // Namespaced model (derivative) - no /library/
                $url = 'https://ollama.com/' . $slug . '/tags';
            } else {
                // Base model - has /library/
                $url = 'https://ollama.com/library/' . $slug . '/tags';
            }
            
            if ($this->fetchUrl($url, $modelFile, false)) {
                $this->fetchedCount++;
                if ($isDerivative && !$resetCounter) {
                    echo "    → Fetched derivative: {$model['name']}\n";
                }
            }
        }
        
        $newlyFetched = $this->fetchedCount - $initialCount;
        if ($newlyFetched > 0 || $skipped > 0) {
            echo "  Fetched {$newlyFetched} new model detail pages";
            if ($skipped > 0) {
                echo " (skipped {$skipped} that already exist)";
            }
            echo "\n";
        } else {
            echo "  All models already fetched (nothing left to fetch)\n";
        }
        echo "\n";
    }
    
    private function parseModelDetails(): void {
        echo "Step 4: Parsing model detail pages...\n";
        
        $skipped404 = 0;
        
        foreach ($this->models as $slug => &$model) {
            // Skip if already parsed (has tags) - prevents duplicate tags when called multiple times
            if (!empty($model['tags'])) {
                continue;
            }
            
            // Handle namespaced models in file path
            $fileSlug = str_replace('/', '_', $slug);
            $modelFile = $this->modelsDir . '/' . $fileSlug . '.html';
            
            if (!file_exists($modelFile)) {
                continue;
            }
            
            // Check if file is a 404 page
            $content = @file_get_contents($modelFile);
            if ($content !== false && strpos($content, '404.') !== false && strpos($content, "That's an error") !== false) {
                $skipped404++;
                // Remove the 404 file so it can be re-fetched if needed
                @unlink($modelFile);
                echo "    Removed 404 file: " . basename($modelFile) . "\n";
                continue;
            }
            
            $dom = new DOMDocument();
            $oldErrors = libxml_use_internal_errors(true);
            
            $loaded = @$dom->loadHTMLFile($modelFile);
            
            if ($loaded === false) {
                $errors = libxml_get_errors();
                libxml_clear_errors();
                libxml_use_internal_errors($oldErrors);
                echo "    Error: Failed to parse HTML";
                if (!empty($errors)) {
                    echo " - " . $errors[0]->message;
                }
                echo "\n";
                continue;
            }
            
            libxml_clear_errors();
            libxml_use_internal_errors($oldErrors);
            
            $xpath = new DOMXPath($dom);
            
            try {
                // Extract downloads
                $this->extractDownloads($xpath, $model);
                
                // Extract features
                $this->extractFeatures($xpath, $model);
                
                // Extract tags
                $this->extractTags($xpath, $model, false);
            } catch (Exception $e) {
                echo "    Warning: Error parsing model details: " . $e->getMessage() . "\n";
                // Continue with next model
            }
        }
        
        if ($skipped404 > 0) {
            echo "  Skipped {$skipped404} models with 404 pages (model not found)\n";
        }
        echo "\n";
    }
    
    private function fetchDerivativeModels(): void {
        echo "Step 5: Fetching derivative models for top 5 popular models...\n";
        
        // Get top 5 models by downloads (excluding nulls)
        $modelsWithDownloads = array_filter($this->models, function($model) {
            return isset($model['downloads']) && $model['downloads'] !== null;
        });
        
        // Sort by downloads descending
        uasort($modelsWithDownloads, function($a, $b) {
            $aDownloads = $a['downloads'] ?? 0;
            $bDownloads = $b['downloads'] ?? 0;
            return $bDownloads <=> $aDownloads;
        });
        
        // Get top 5
        $top5 = array_slice($modelsWithDownloads, 0, 5, true);
        
        if (empty($top5)) {
            echo "  No models with downloads found, skipping derivative fetch\n\n";
            return;
        }
        
        echo "  Top 5 models by downloads:\n";
        foreach ($top5 as $slug => $model) {
            echo "    - {$model['name']}: " . number_format($model['downloads']) . " downloads\n";
        }
        echo "\n";
        
        foreach ($top5 as $slug => $model) {
            // Check total fetch limit (across both main and derivative models)
            if ($this->fetchedCount >= self::MAX_FETCH_PER_RUN) {
                echo "  Reached total limit of " . self::MAX_FETCH_PER_RUN . " fetches per run\n";
                break;
            }
            
            $modelName = $model['name'];
            echo "  Fetching derivatives for: {$modelName}\n";
            
            // Fetch search results for this model
            $searchUrl = 'https://ollama.com/search?q=' . urlencode($modelName);
            $searchFile = $this->cacheDir . '/popular-' . $slug . '.html';
            
            if (!$this->shouldFetch($searchFile)) {
                echo "    Using cached search results\n";
            } else {
                if ($this->fetchUrl($searchUrl, $searchFile)) {
                    echo "    Fetched search results\n";
                } else {
                    echo "    Failed to fetch search results\n";
                    continue;
                }
            }
            
            // Parse search results to find derivatives
            $derivatives = $this->parseDerivativeSearch($searchFile, $modelName);
            
            if (empty($derivatives)) {
                echo "    No derivatives found\n";
                continue;
            }
            
            echo "    Found " . count($derivatives) . " derivatives:\n";
            
            // Add all discovered derivatives to the models array (queue them for future fetching)
            foreach ($derivatives as $index => $derivative) {
                $derivativeSlug = $derivative['slug'];
                $pullsFormatted = number_format($derivative['pulls']);
                echo "      " . ($index + 1) . ". {$derivative['name']} ({$pullsFormatted} pulls)\n";
                
                // Add to models array if not already there (queue for future fetching)
                if (!isset($this->models[$derivativeSlug])) {
                    $this->models[$derivativeSlug] = [
                        'name' => $derivative['name'],
                        'description' => '',
                        'features' => [],
                        'tags' => [],
                        'downloads' => null
                    ];
                    // Mark as derivative
                    $this->derivativeModels[$derivativeSlug] = true;
                }
            }
            
            // Fetch up to 5 most popular derivatives (but respect total limit)
            $fetched = 0;
            foreach ($derivatives as $derivative) {
                // Check total fetch limit
                if ($this->fetchedCount >= self::MAX_FETCH_PER_RUN) {
                    echo "    Reached total limit of " . self::MAX_FETCH_PER_RUN . " fetches per run\n";
                    break;
                }
                
                // Limit to 5 derivatives per model
                if ($fetched >= 5) {
                    break;
                }
                
                $derivativeSlug = $derivative['slug'];
                // Handle namespaced models in file path (e.g., huihui_ai/gemma3-abliterated -> huihui_ai_gemma3-abliterated.html)
                $fileSlug = str_replace('/', '_', $derivativeSlug);
                $derivativeFile = $this->modelsDir . '/' . $fileSlug . '.html';
                
                // Check if we already have complete information for this derivative
                $alreadyHasInfo = false;
                if (!empty($this->models[$derivativeSlug]['tags'])) {
                    $alreadyHasInfo = true;
                } elseif (file_exists($derivativeFile)) {
                    // File exists, we'll parse it later, so we have the info
                    $alreadyHasInfo = true;
                }
                
                if ($alreadyHasInfo) {
                    // Already have this derivative's information, skip it
                    continue;
                }
                
                // Fetch the derivative detail page (use /tags for full tag list)
                // Derivatives (namespaced) don't have /library/ in the URL
                $derivativeUrl = 'https://ollama.com/' . $derivativeSlug . '/tags';
                if ($this->fetchUrl($derivativeUrl, $derivativeFile, false)) {
                    $fetched++;
                    $this->fetchedCount++;
                    $pullsFormatted = number_format($derivative['pulls']);
                    echo "    → Fetched new derivative: {$derivative['name']} ({$pullsFormatted} pulls)\n";
                }
            }
            
            if ($fetched > 0) {
                echo "    Fetched {$fetched} new derivative(s)\n";
            }
        }
        
        echo "\n";
    }
    
    private function debugDerivativeSearch(string $modelName): void {
        echo "Debug: Testing derivative search for: {$modelName}\n";
        echo str_repeat('=', 60) . "\n\n";
        
        // Find the model in our models array to get the slug
        $modelSlug = null;
        foreach ($this->models as $slug => $model) {
            if ($model['name'] === $modelName || $slug === $modelName) {
                $modelSlug = $slug;
                break;
            }
        }
        
        if ($modelSlug === null) {
            echo "Error: Model '{$modelName}' not found in models list\n";
            echo "Available models:\n";
            foreach ($this->models as $slug => $model) {
                echo "  - {$model['name']} (slug: {$slug})\n";
            }
            return;
        }
        
        echo "Using slug: {$modelSlug}\n\n";
        
        // Fetch or use cached search results
        $searchUrl = 'https://ollama.com/search?q=' . urlencode($modelName);
        $searchFile = $this->cacheDir . '/popular-' . $modelSlug . '.html';
        
        echo "Search URL: {$searchUrl}\n";
        echo "Cache file: {$searchFile}\n\n";
        
        if (!$this->shouldFetch($searchFile)) {
            echo "Using cached search results\n";
        } else {
            echo "Fetching search results...\n";
            if (!$this->fetchUrl($searchUrl, $searchFile)) {
                echo "Error: Failed to fetch search results\n";
                return;
            }
        }
        
        if (!file_exists($searchFile)) {
            echo "Error: Search results file not found\n";
            return;
        }
        
        echo "File size: " . filesize($searchFile) . " bytes\n\n";
        
        // Parse and display all found models
        $derivatives = $this->parseDerivativeSearch($searchFile, $modelName);
        
        echo "Found " . count($derivatives) . " derivatives:\n";
        echo str_repeat('-', 60) . "\n";
        
        foreach ($derivatives as $index => $derivative) {
            $pullsFormatted = number_format($derivative['pulls']);
            echo ($index + 1) . ". {$derivative['name']}\n";
            echo "   Slug: {$derivative['slug']}\n";
            echo "   Pulls: {$pullsFormatted}\n";
            echo "\n";
        }
        
        echo str_repeat('=', 60) . "\n";
    }
    
    private function debugTagExtraction(string $modelSlug): void {
        echo "Debug: Testing tag extraction for: $modelSlug\n";
        echo str_repeat('=', 60) . "\n\n";
        
        // Handle namespaced models in file path
        $fileSlug = str_replace('/', '_', $modelSlug);
        $modelFile = $this->modelsDir . '/' . $fileSlug . '.html';
        
        if (!file_exists($modelFile)) {
            echo "Error: Model file not found: $modelFile\n";
            echo "Fetching it first...\n";
            
            // Check if it's a namespaced model (derivative) or base model
            if (strpos($modelSlug, '/') !== false) {
                // Namespaced model (derivative) - no /library/
                $url = 'https://ollama.com/' . $modelSlug . '/tags';
            } else {
                // Base model - has /library/
                $url = 'https://ollama.com/library/' . $modelSlug . '/tags';
            }
            if (!$this->fetchUrl($url, $modelFile, false)) {
                echo "Error: Failed to fetch model page\n";
                return;
            }
        }
        
        echo "Using file: $modelFile\n";
        echo "File size: " . filesize($modelFile) . " bytes\n\n";
        
        $dom = new DOMDocument();
        $oldErrors = libxml_use_internal_errors(true);
        
        $loaded = @$dom->loadHTMLFile($modelFile);
        
        if ($loaded === false) {
            $errors = libxml_get_errors();
            libxml_clear_errors();
            libxml_use_internal_errors($oldErrors);
            echo "Error: Failed to parse HTML\n";
            foreach ($errors as $error) {
                echo "  " . $error->message . "\n";
            }
            return;
        }
        
        libxml_clear_errors();
        libxml_use_internal_errors($oldErrors);
        
        $xpath = new DOMXPath($dom);
        
        // Create a dummy model array for testing
        $testModel = [
            'name' => $modelSlug,
            'description' => '',
            'features' => [],
            'tags' => [],
            'downloads' => null
        ];
        
        echo "Extracting tags with debug output...\n";
        echo str_repeat('-', 60) . "\n";
        
        $this->extractTags($xpath, $testModel, true);
        
        echo str_repeat('-', 60) . "\n";
        echo "\nFinal model data:\n";
        echo json_encode($testModel, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
        
        echo str_repeat('=', 60) . "\n";
    }
    
    private function parseDerivativeSearch(string $searchFile, string $originalModelName): array {
        $derivatives = [];
        
        if (!file_exists($searchFile)) {
            return $derivatives;
        }
        
        $dom = new DOMDocument();
        $oldErrors = libxml_use_internal_errors(true);
        
        $loaded = @$dom->loadHTMLFile($searchFile);
        
        if ($loaded === false) {
            libxml_clear_errors();
            libxml_use_internal_errors($oldErrors);
            return $derivatives;
        }
        
        libxml_clear_errors();
        libxml_use_internal_errors($oldErrors);
        
        $xpath = new DOMXPath($dom);
        
        // Find all model list items - try multiple XPath patterns
        $listItems = $xpath->query('//*[@id="searchresults"]/ul/li');
        
        // If that doesn't work, try alternative structure
        if ($listItems === false || $listItems->length === 0) {
            $listItems = $xpath->query('//ul[contains(@class, "divide-y")]/li');
        }
        
        if ($listItems === false || $listItems->length === 0) {
            return $derivatives;
        }
        
        foreach ($listItems as $li) {
            // Get the anchor tag - try multiple ways to find it
            // First try /library/ links, then try any link that looks like a model link
            $anchor = $xpath->query('.//a[contains(@href, "/library/")]', $li)->item(0);
            if ($anchor === null) {
                // Try links that match /author/model or /model pattern (without /library/)
                $anchor = $xpath->query('.//a[starts-with(@href, "/") and not(contains(@href, "/public/")) and not(contains(@href, "/signin")) and not(contains(@href, "/download")) and not(contains(@href, "/docs")) and not(contains(@href, "/cloud")) and not(contains(@href, "/models")) and not(contains(@href, "/search"))]', $li)->item(0);
            }
            if ($anchor === null) {
                // Fallback: just get any anchor
                $anchor = $xpath->query('.//a', $li)->item(0);
            }
            if ($anchor === null) {
                continue;
            }
            
            // Extract model slug from href (including namespaces like huihui_ai/gemma3-abliterated)
            $href = $anchor->getAttribute('href');
            if (empty($href)) {
                continue;
            }
            
            // Try to extract model slug - handle multiple formats:
            // 1. /library/model or /library/author/model
            // 2. /author/model (without /library/)
            // 3. /model (without /library/ and without author)
            $modelSlug = null;
            if (preg_match('#/library/(.+?)(?:/tags|$)#', $href, $matches)) {
                $modelSlug = $matches[1];
            } elseif (preg_match('#^/([^/]+(?:/[^/]+)*?)(?:/tags|$)#', $href, $matches)) {
                // Match /author/model or /model (but exclude common non-model paths)
                $potentialSlug = $matches[1];
                // Skip if it's a known non-model path
                if (!in_array($potentialSlug, ['', 'signin', 'download', 'docs', 'cloud', 'models', 'search', 'public'])) {
                    $modelSlug = $potentialSlug;
                }
            }
            
            if ($modelSlug === null) {
                continue;
            }
            
            // Skip if it's the original model itself (handle both simple and namespaced names)
            // For namespaced models, check if the base name matches the original exactly
            // But allow derivatives like "gemma3-abliterated" when searching for "gemma3"
            $baseName = basename($modelSlug); // Get the part after the last /
            
            // Skip exact matches only - allow derivatives (e.g., "gemma3-abliterated" is a derivative of "gemma3")
            if ($modelSlug === $originalModelName) {
                continue;
            }
            
            // Skip if base name exactly matches (e.g., "author/gemma3" when searching for "gemma3")
            // But allow if it's a derivative (contains the original name but with additional text)
            if ($baseName === $originalModelName) {
                continue;
            }
            
            // Also skip if the slug starts with the original name followed by / (e.g., "gemma3/something")
            if (strpos($modelSlug, $originalModelName . '/') === 0) {
                continue;
            }
            
            // Extract model name
            $nameNode = $xpath->query('.//div[1]/h2/span', $anchor)->item(0);
            if ($nameNode === null) {
                $nameNode = $xpath->query('.//h2/span', $anchor)->item(0);
            }
            $modelName = $nameNode !== null ? trim($nameNode->textContent) : $modelSlug;
            
            // Extract pulls from: //*[@id="searchresults"]/ul/li[1]/a/div[2]/p/span[1]/span[1]
            $pullsNode = $xpath->query('.//div[2]/p/span[1]/span[1]', $anchor)->item(0);
            $pulls = 0;
            
            if ($pullsNode !== null) {
                $pullsText = trim($pullsNode->textContent);
                $cleanText = str_replace(',', '', $pullsText);
                
                // Parse pulls number (similar to downloads parsing)
                if (preg_match('/([\d.]+)\s*([KMGT]?)/i', $cleanText, $matches)) {
                    $number = floatval($matches[1]);
                    $suffix = strtoupper($matches[2]);
                    
                    switch ($suffix) {
                        case 'K':
                            $number *= 1000;
                            break;
                        case 'M':
                            $number *= 1000000;
                            break;
                        case 'G':
                            $number *= 1000000000;
                            break;
                        case 'T':
                            $number *= 1000000000000;
                            break;
                    }
                    
                    $pulls = intval($number);
                } elseif (is_numeric($cleanText)) {
                    $pulls = intval($cleanText);
                }
            }
            
            $derivatives[] = [
                'slug' => $modelSlug,
                'name' => $modelName,
                'pulls' => $pulls
            ];
        }
        
        // Sort by pulls descending
        usort($derivatives, function($a, $b) {
            return $b['pulls'] <=> $a['pulls'];
        });
        
        return $derivatives;
    }
    
    private function extractDownloads(DOMXPath $xpath, array &$model): void {
        // Extract downloads from: /html/body/div/div[1]/div[2]/div[2]/p/span[1]/span[1]
        $downloadsNode = $xpath->query('/html/body/div/div[1]/div[2]/div[2]/p/span[1]/span[1]')->item(0);
        
        if ($downloadsNode !== null) {
            $downloadsText = trim($downloadsNode->textContent);
            
            // Parse downloads number (e.g., "2,931", "1.5M", "50.2K")
            // Remove commas and try to parse
            $cleanText = str_replace(',', '', $downloadsText);
            
            // Try to parse as number
            if (preg_match('/([\d.]+)\s*([KMGT]?)/i', $cleanText, $matches)) {
                $number = floatval($matches[1]);
                $suffix = strtoupper($matches[2]);
                
                // Convert to actual number
                switch ($suffix) {
                    case 'K':
                        $number *= 1000;
                        break;
                    case 'M':
                        $number *= 1000000;
                        break;
                    case 'G':
                        $number *= 1000000000;
                        break;
                    case 'T':
                        $number *= 1000000000000;
                        break;
                }
                
                $model['downloads'] = intval($number);
            } elseif (is_numeric($cleanText)) {
                $model['downloads'] = intval($cleanText);
            } else {
                // Store as string if we can't parse it
                $model['downloads'] = $downloadsText;
            }
        }
    }
    
    private function extractFeatures(DOMXPath $xpath, array &$model): void {
        // Find the features div: <div class="flex flex-wrap space-x-2">
        $featuresDiv = $xpath->query('//div[contains(@class, "flex") and contains(@class, "flex-wrap") and contains(@class, "space-x-2")]')->item(0);
        
        if ($featuresDiv === null) {
            return;
        }
        
        // Find all span elements within this div
        $spans = $xpath->query('.//span', $featuresDiv);
        
        if ($spans === false) {
            return;
        }
        
        foreach ($spans as $span) {
            $classes = $span->getAttribute('class');
            $text = trim($span->textContent);
            
            // Check for bg-indigo-50 (tools, thinking)
            if (strpos($classes, 'bg-indigo-50') !== false) {
                $feature = strtolower($text);
                if (!in_array($feature, $model['features'])) {
                    $model['features'][] = $feature;
                }
            }
            
            // Ignore bg-cyan-50 (cloud) and size tags
        }
    }
    
    private function extractTags(DOMXPath $xpath, array &$model, bool $debug = false): void {
        // Find the table with tag information
        // The structure is: <div class="min-w-full divide-y divide-gray-200">
        $tableDiv = $xpath->query('//div[contains(@class, "min-w-full") and contains(@class, "divide-y")]')->item(0);
        
        if ($tableDiv === null) {
            if ($debug) {
                echo "DEBUG: Could not find table div with class 'min-w-full divide-y'\n";
            }
            return;
        }
        
        if ($debug) {
            echo "DEBUG: Found table div\n";
        }
        
        // Find all rows (can be <a> tags or <div class="group">)
        // Handle both base models (/library/model:tag) and derivatives (/author/model:tag)
        $rows = $xpath->query('.//a[contains(@href, "/library/") or (contains(@href, ":") and not(starts-with(@href, "http")))] | .//div[contains(@class, "group") and contains(@class, "px-4")]', $tableDiv);
        
        if ($debug) {
            echo "DEBUG: Found " . $rows->length . " rows\n";
        }
        
        $processedTags = [];
        
        foreach ($rows as $rowIndex => $row) {
            $tag = [];
            
            if ($debug) {
                echo "\nDEBUG: Processing row " . ($rowIndex + 1) . " (nodeName: " . $row->nodeName . ")\n";
            }
            
            // Extract tag name from href (works for both <a> and <a> inside <div>)
            $link = null;
            if ($row->nodeName === 'a') {
                $link = $row;
            } else {
                // Look for links with /library/ (base models) or links with : (tag links for derivatives)
                $link = $xpath->query('.//a[contains(@href, "/library/") or (contains(@href, ":") and not(starts-with(@href, "http")))]', $row)->item(0);
            }
            
            if ($link === null) {
                if ($debug) {
                    echo "  DEBUG: No link found in row\n";
                }
                continue;
            }
            
            $href = $link->getAttribute('href');
            // Handle both formats:
            // Base models: /library/model:tag
            // Derivatives: /author/model:tag
            $tagName = null;
            if (preg_match('#/library/[^:]+:(.+)$#', $href, $matches)) {
                $tagName = $matches[1];
            } elseif (preg_match('#^/[^:]+:(.+)$#', $href, $matches)) {
                // Derivative model format: /author/model:tag
                $tagName = $matches[1];
            }
            
            if ($tagName === null) {
                if ($debug) {
                    echo "  DEBUG: Could not extract tag name from href: $href\n";
                }
                continue;
            }
            
            if ($debug) {
                echo "  DEBUG: Tag name: $tagName\n";
            }
            
            // Skip if we already processed this tag
            if (isset($processedTags[$tagName])) {
                if ($debug) {
                    echo "  DEBUG: Already processed this tag, skipping\n";
                }
                continue;
            }
            
            $tag['name'] = $tagName;
            
            // Extract size, context, and input using DOM
            // Input can be in either <p> or <div> with col-span-2 and text-neutral-500
            $dataNodes = $xpath->query('.//p[contains(@class, "col-span-2") and contains(@class, "text-neutral-500")] | .//div[contains(@class, "col-span-2") and contains(@class, "text-neutral-500")]', $row);
            
            if ($debug) {
                echo "  DEBUG: Found " . $dataNodes->length . " data nodes with col-span-2 and text-neutral-500\n";
            }
            
            if ($dataNodes->length >= 3) {
                $size = trim($dataNodes->item(0)->textContent);
                $context = trim($dataNodes->item(1)->textContent);
                $input = trim($dataNodes->item(2)->textContent);
                
                if ($debug) {
                    echo "  DEBUG: Extracted values:\n";
                    echo "    size: '$size'\n";
                    echo "    context: '$context'\n";
                    echo "    input: '$input'\n";
                }
                
                if (!empty($size)) $tag['size'] = $size;
                if (!empty($context)) $tag['context'] = $context;
                if (!empty($input)) $tag['input'] = $input;
            } else {
                if ($debug) {
                    echo "  DEBUG: Not enough data nodes found. Trying alternative queries...\n";
                    // Try alternative queries to see what's available
                    $altNodes = $xpath->query('.//p[contains(@class, "text-neutral-500")] | .//div[contains(@class, "text-neutral-500")]', $row);
                    echo "  DEBUG: Found " . $altNodes->length . " nodes with text-neutral-500\n";
                    if ($altNodes->length > 0) {
                        foreach ($altNodes as $i => $node) {
                            echo "    Node $i (" . $node->nodeName . "): '" . trim($node->textContent) . "'\n";
                        }
                    }
                    // Show row HTML structure
                    $rowHtml = $row->ownerDocument->saveHTML($row);
                    echo "  DEBUG: Row HTML (first 500 chars):\n" . substr($rowHtml, 0, 500) . "\n";
                }
            }
            
            // Only add tag if we have a name and at least some metadata
            if (!empty($tag['name']) && (!empty($tag['size']) || !empty($tag['context']) || !empty($tag['input']))) {
                $model['tags'][] = $tag;
                $processedTags[$tagName] = true;
                if ($debug) {
                    echo "  DEBUG: Added tag to model\n";
                }
            } else {
                if ($debug) {
                    echo "  DEBUG: Tag not added - missing metadata\n";
                    echo "  DEBUG: Tag array: " . json_encode($tag) . "\n";
                }
            }
        }
        
        if ($debug) {
            echo "\nDEBUG: Total tags extracted: " . count($model['tags']) . "\n";
        }
    }
    
    
    private function mergeAndGenerateJson(): array {
        echo "Step 7: Merging data and generating JSON output...\n";
        
        // Merge original models with scraped data
        // Start with all original models
        $merged = [];
        
        foreach ($this->originalModels as $name => $originalModel) {
            // Use name as key for original models (they don't have slugs)
            $merged[$name] = [
                'name' => $name,
                'slug' => null, // Original models don't have slugs
                'description' => $originalModel['description'] ?? '',
                'features' => [],
                'tags' => [],
                'downloads' => null
            ];
        }
        
        $baseModelsAdded = 0;
        $derivativesAdded = 0;
        
        // Merge in scraped data (tags and features from library pages)
        foreach ($this->models as $slug => $scrapedModel) {
            $name = $scrapedModel['name'];
            $isDerivative = isset($this->derivativeModels[$slug]);
            
            // Check if model exists by name (for original models) or by slug (for scraped models)
            $foundKey = null;
            if (isset($merged[$name])) {
                // Found by name (original model)
                $foundKey = $name;
            } elseif (isset($merged[$slug])) {
                // Found by slug (already added scraped model)
                $foundKey = $slug;
            }
            
            if ($foundKey !== null) {
                // Update existing model with scraped tags/features/downloads
                $merged[$foundKey]['features'] = $scrapedModel['features'];
                $merged[$foundKey]['tags'] = $scrapedModel['tags'];
                if (isset($scrapedModel['downloads'])) {
                    $merged[$foundKey]['downloads'] = $scrapedModel['downloads'];
                }
                // Update slug if it wasn't set
                if (empty($merged[$foundKey]['slug'])) {
                    $merged[$foundKey]['slug'] = $slug;
                }
            } else {
                // New model from scraping, add it (includes derivatives)
                // Use slug as key to ensure uniqueness (derivatives can have same display name)
                $key = $slug; // Use slug instead of name to prevent overwrites
                $merged[$key] = [
                    'name' => $name,
                    'slug' => $slug, // Include slug in output for uniqueness
                    'description' => $scrapedModel['description'],
                    'features' => $scrapedModel['features'],
                    'tags' => $scrapedModel['tags'],
                    'downloads' => $scrapedModel['downloads'] ?? null
                ];
                
                if ($isDerivative) {
                    $derivativesAdded++;
                } else {
                    $baseModelsAdded++;
                }
            }
        }
        
        $totalUnique = count($merged);
        
        // Convert to indexed array and filter out models without tags
        $output = array_values(array_filter($merged, function($model) {
            return !empty($model['tags']);
        }));
        
        // Count derivatives in output by building a name-to-derivative map
        $derivativeNames = [];
        foreach ($this->derivativeModels as $derivativeSlug => $_) {
            if (isset($this->models[$derivativeSlug])) {
                $derivativeNames[$this->models[$derivativeSlug]['name']] = true;
            }
        }
        
        $derivativesInOutput = 0;
        $baseInOutput = 0;
        foreach ($output as $model) {
            if (isset($derivativeNames[$model['name']])) {
                $derivativesInOutput++;
            } else {
                $baseInOutput++;
            }
        }
        
        echo "  Merged {$baseModelsAdded} new base models and {$derivativesAdded} derivatives\n";
        echo "  In output: {$baseInOutput} base models, {$derivativesInOutput} derivatives (all have tags)\n";
        
        if (empty($output)) {
            echo "  Warning: No models with tags to output\n";
            return ['total_unique' => $totalUnique, 'with_tags' => 0];
        }
        
        // Sort by name
        usort($output, function($a, $b) {
            return strcasecmp($a['name'], $b['name']);
        });
        
        $json = json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        
        // Change indentation from 4 spaces to 2 spaces (handle all indentation levels)
        $json = preg_replace_callback('/^([ ]+)/m', function($matches) {
            $spaces = strlen($matches[1]);
            return str_repeat('  ', intval($spaces / 4));
        }, $json);
        
        if ($json === false) {
            $error = json_last_error_msg();
            throw new Exception("Failed to encode JSON: " . ($error ?: 'Unknown error'));
        }
        
        // Validate JSON by decoding it
        $decoded = json_decode($json, true);
        if ($decoded === null) {
            $error = json_last_error_msg();
            if (json_last_error() !== JSON_ERROR_NONE) {
                throw new Exception("Generated invalid JSON: " . ($error ?: 'Unknown error'));
            }
        }
        
        // Ensure output directory exists
        $outputDir = dirname($this->outputFile);
        if (!is_dir($outputDir)) {
            $this->createDirectory($outputDir);
        }
        
        // Write to temporary file first, then rename (atomic operation)
        $tempFile = $this->outputFile . '.tmp';
        if (file_put_contents($tempFile, $json) === false) {
            throw new Exception("Failed to write JSON to temporary file {$tempFile}");
        }
        
        // Validate the temp file
        $tempContent = file_get_contents($tempFile);
        $tempDecoded = json_decode($tempContent, true);
        if ($tempDecoded === null && json_last_error() !== JSON_ERROR_NONE) {
            unlink($tempFile);
            throw new Exception("Temporary JSON file is invalid");
        }
        
        // Rename temp file to final file (atomic)
        if (!rename($tempFile, $this->outputFile)) {
            @unlink($tempFile);
            throw new Exception("Failed to rename temporary file to {$this->outputFile}");
        }
        
        echo "  Generated: " . basename($this->outputFile) . "\n";
        echo "  Models: " . count($output) . "\n";
        
        return [
            'total_unique' => $totalUnique,
            'with_tags' => count($output)
        ];
    }
}

// Main execution
try {
    $scraper = new OllamaModelScraper();
    $scraper->run();
} catch (Exception $e) {
    echo "Fatal error: " . $e->getMessage() . "\n";
    exit(1);
}

