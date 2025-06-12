# Error Message Handling for OpenRouter API

This document describes the error handling implementation for OpenRouter API failures in the LLM Toolkit.

## Overview

When OpenRouter returns API errors (like "No endpoints found that support tool use"), the system now creates user-friendly error messages instead of crashing or showing technical error details to users.

## Components

### 1. OpenrouterErrorHandler (`lib/llm_toolkit/openrouter_error_handler.rb`)

Responsible for:
- Converting technical error messages to user-friendly ones in French
- Determining which errors should create user messages vs raise exceptions
- Providing specific guidance for different error types

**Example error transformations:**
- "No endpoints found that support tool use" → "Le modèle sélectionné ne prend pas en charge les outils avancés..."
- Rate limiting errors → "Le service est temporairement surchargé..."
- Model not found → "Le modèle demandé n'est pas disponible actuellement..."

### 2. LlmProvider Error Patch (`lib/llm_toolkit/llm_provider_error_patch.rb`)

Modifies the `stream_openrouter` method to:
- Detect error chunks in the streaming response
- Call the error handler for user-friendly errors
- Yield error chunks to the service instead of raising exceptions
- Return special error response objects

### 3. Streaming Service Error Patch (`lib/llm_toolkit/streaming_service_error_patch.rb`)

Enhances `CallStreamingLlmWithToolService` to:
- Handle new 'error' chunk type
- Create error messages with `is_error: true` flag
- Set appropriate finish_reason for error messages

### 4. Conversation History Patch (`lib/llm_toolkit/conversation_error_patch.rb`)

Updates the `history` method in `Conversation` to:
- Filter out error messages from conversation context
- Prevent error messages from affecting future LLM calls

### 5. Database Migration

Adds `is_error` boolean column to `llm_toolkit_messages` table to mark error messages.

### 6. UI Components

**CSS Styling** (`app/assets/stylesheets/llm_toolkit/error_messages.css`):
- Error message styling with warning icons
- Dark mode support
- Distinguishes error messages from normal content

**Helper Methods** (`app/helpers/llm_toolkit/message_helper.rb`):
- `message_css_classes(message)` - Returns appropriate CSS classes
- `error_message?(message)` - Determines if message is an error
- `message_icon(message)` - Returns appropriate icons

## Usage

### In Views

```erb
<div class="<%= message_css_classes(message) %>">
  <%= message_icon(message) %>
  <div class="message-content">
    <%= simple_format(message.content) %>
  </div>
</div>
```

### Error Message Properties

Error messages have these characteristics:
- `is_error: true` - Boolean flag marking them as errors
- `role: 'assistant'` - Appears as assistant messages
- `finish_reason: 'error'` - Special finish reason
- Excluded from conversation history for future LLM calls
- Special CSS styling in the UI

### Supported Error Types

1. **Tool Support Errors**: Model doesn't support tools
2. **Rate Limiting**: Too many requests, quota exceeded
3. **Model Availability**: Model not found or unavailable
4. **Content Filtering**: Safety policy violations
5. **Context Length**: Message too long for model
6. **Authentication**: API key or billing issues
7. **Network**: Timeout and connection issues

## Configuration

The error handler uses French messages by default. To customize:

1. Extend `OpenrouterErrorHandler.create_user_friendly_message`
2. Add new error patterns to `should_create_error_message?`
3. Modify CSS classes in `error_messages.css`

## Flow Diagram

```
OpenRouter API Error
        ↓
Error detected in streaming chunk
        ↓
OpenrouterErrorHandler.should_create_error_message?
        ↓
    Yes → Create user-friendly message
    No  → Raise exception as before
        ↓
Yield 'error' chunk to service
        ↓
Service creates Message with is_error: true
        ↓
UI displays with error styling
        ↓
Message excluded from future conversation history
```

## Testing

To test error handling:

1. Select a model that doesn't support tools (like many open-source models)
2. Send a message that would trigger tool usage
3. Observe user-friendly error message instead of technical error
4. Verify error message doesn't appear in conversation history for subsequent messages

## Migration Instructions

1. Run the migration: `rails db:migrate`
2. Restart the Rails application to load the patches
3. CSS and helper files are automatically included
4. No view changes required if using standard message display patterns