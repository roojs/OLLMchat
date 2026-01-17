# 5.1. Planning Modes

## Overview

Different planning modes for the chat: ask mode, planning mode, do stuff mode, and agent mode.

## Status

⏳ **TODO** - To be implemented.

## Implementation Details

### Modes
1. **Ask Mode** - Simple Q&A mode
2. **Planning Mode** - For planning and strategizing
3. **Do Stuff Mode** - Action-oriented mode
4. **Agent Mode** - Autonomous agent mode

### Features
- Mode selection in UI
- Different prompt templates per mode
- Mode-specific tool availability
- Mode-specific behavior

### Files to Create/Modify
- Mode management system
- Prompt templates for each mode
- UI for mode selection
- Mode-specific configurations

## Orchestrator Architecture

### Overview
The coder agent will be transformed into an **orchestrator** that manages specialized agents through tools. The orchestrator's job is to coordinate agents to solve tasks needed by the user.

### Agent Types
The orchestrator has access to three specialized agents via tools:

1. **Analysis Agent** - Understands user requirements and needs
2. **Planning Agent** - Creates and updates implementation plans
3. **Implementation Agent** - Executes plans to implement changes

### Tools for Orchestrator
The orchestrator uses tools to interact with agents:
- **Planning Tool** - Invokes the planning agent to create/update plans
- **Analysis Tool** - Invokes the analysis agent to understand requirements
- **Implementation Tool** - Invokes the implementation agent to execute plans

### Workflow
The orchestrator follows this flow:

1. **Analysis Phase**
   - Work out what the user wants using the analysis agent
   - Understand requirements and constraints

2. **Planning Phase**
   - Ask the planner (via planning tool) to create a plan
   - Plan is stored in a file for review
   - Present the plan to the user for approval

3. **Plan Refinement**
   - If changes are needed, ask the planner to update the plan based on user requirements
   - Iterate until the user is happy with the plan

4. **Implementation Phase**
   - Once the user approves the plan, ask the implementer (via implementation tool) to implement the plan
   - Execute the plan step by step

### Implementation Notes
- Design mode system architecture
- Create prompt templates for each mode
- Define mode-specific behaviors
- UI for switching between modes
- Store mode preference per chat
- Transform coder agent into orchestrator
- Create tool interfaces for agent communication
- Implement planning tool for plan creation/updates
- Implement analysis tool for requirement understanding
- Implement implementation tool for plan execution
- Create plan file format and storage
- Add user approval workflow for plans