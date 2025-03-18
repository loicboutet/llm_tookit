# Changelog

All notable changes to LlmToolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-08-XX

### Added
- Initial release of LlmToolkit
- Core `Conversable` concern for making models participate in LLM conversations
- Conversations and Messages models for persisting chat history
- Tool framework with DSL for creating custom tools
- Support for Anthropic Claude and OpenRouter API providers
- Tool execution and result tracking
- Database migrations for all required models
- Comprehensive documentation (README, TOOLS, ARCHITECTURE, USAGE)
- Basic generator for installation
- Configuration options for customizing behavior
- Error handling for API interactions

### Known Limitations
- Limited test coverage
- Currently supports only Anthropic and OpenRouter providers
- Asynchronous tool handling requires custom implementation for complex cases

## [Unreleased]

- OpenAI provider support
- Enhanced test coverage
- Improved async tool handling
- WebSocket integration for real-time updates