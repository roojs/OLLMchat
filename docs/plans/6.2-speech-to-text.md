# 6.2 Speech to Text

## Overview
The goal is to integrate Speech-to-Text (STT) capabilities into OLLMchat, allowing users to interact with agents using voice commands. This involves capturing audio from the microphone and transcribing it into text that can be processed by the existing chat pipeline.

## Objectives
- Evaluate various STT implementation alternatives (local vs. cloud, library vs. API).
- Define a high-level architecture for audio capture and transcription.
- Determine how to integrate the transcription result into the existing message flow.
- Assess privacy, latency, and resource usage implications of each alternative.

## Alternatives to Evaluate

### 1. Local/On-Device Solutions (Privacy Focused)
*Pros: High privacy, no API costs, works offline.*
*Cons: Higher CPU/GPU usage, potentially higher latency, larger installation footprint.*

- **OpenAI Whisper (Local):** Running Whisper models locally via `whisper.cpp` or python bindings.
- **Vosk:** A lightweight, offline speech recognition toolkit that supports many languages and is efficient for real-run environments.
- **PocketSphinx:** An older but extremely low-resource option for simple command recognition.

### 2. Cloud-Based APIs (Performance Focused)
*Pros: Extremely high accuracy, low local resource usage, easy implementation.*
*Cons: Requires internet connection, privacy concerns (data leaves device), recurring costs.*

- **OpenAI Whisper API:** Using the hosted version of Whisper via OpenAI's API.
- **Google Cloud Speech-to-Text:** Highly scalable and accurate but complex setup.
- **AssemblyAI:** Developer-friendly API with great features like speaker diarization and auto-punctuation.

### 3. OS-Native APIs
*Pros: Zero additional footprint, uses system capabilities.*
*Cons: Platform-dependent (Linux/Wayland support might be limited), varying quality across versions.*

- **Speech Dispatcher (Linux):** Utilizing existing Linux accessibility frameworks.

## Evaluation Criteria
| Criterion | Local (Whisper.cpp) | Cloud (OpenAI API) | Native OS |
| :--- | :--- | :--- | :--- |
| **Privacy** | Excellent | Low | High |
| **Latency** | Medium/High | Low (network dependent) | Very Low |
| **Accuracy**| High | Very High | Medium |
| **Cost** | Free (Resource cost) | Per-use API Cost | Free |
| **Reliability**| Offline capable | Requires Internet | Highly reliable |

## Implementation Steps (Proposed)
1. **Research Phase:** Benchmark `whisper.cpp` against a cloud API for latency and accuracy on target hardware.
2. **Audio Capture Module:** Implement a way to capture audio streams from the microphone (using PulseAudio/PipeWire).
3. **STT Integration Layer:** Create an abstraction layer that allows switching between different STT providers.
4. **UI/UX Integration:** Add a "Microphone" button to the chat input composer and provide visual feedback during recording/processing.
5. **Testing:** Verify transcription accuracy for various accents and noisy environments.

## Open Questions
- How should we handle long-form audio vs. short commands?
- Do we want to support "push-to-talk" or "always listening" (wake word) functionality?
- Should the STT processing happen in a separate worker process to avoid UI freezing?
