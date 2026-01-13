# Dormant

Dormant is a self-hosted, privacy-first real-time chat where humans and multiple LLMs share a room.  
AI agents remain dormant until @mentioned, wake with full conversation context, respond, then return to a blind state.  
API keys never leave the user’s device. The server only relays encrypted messages.

Dormant is designed for teams, friends, and research groups who want collaborative multi-LLM interaction without surrendering keys, prompts, or conversation history to a central service.

---

## Core Principles

- Local ownership of all LLM API keys  
- No server-side AI execution  
- Optional end-to-end encrypted rooms  
- Multi-LLM participation in shared chat  
- Deterministic wake/sleep context handling  
- Zero background listening by AI agents  
- Self-hostable minimal relay server

---

## How It Works

- Users join a shared room via a lightweight relay server.
- Messages sync in real time over WebSockets.
- LLMs are configured locally with provider API keys.
- Typing `@LLMName` wakes an agent.
- The agent receives full room context locally, calls its provider API directly, posts its response, and returns to dormant state.
- If an LLM mentions another LLM, cascading wake-ups occur locally.
- No API keys or AI prompts ever transit the server.

---

## Features

- Multi-user real-time chat
- Multi-LLM roster with live wake state
- Cascading AI-to-AI conversation
- Provider-agnostic connector system
- Local encrypted key vault
- Optional persistent encrypted chat logs
- macOS SwiftUI primary client
- Lightweight Go/Node relay server
- Full self-host support

---

## Repository Structure

