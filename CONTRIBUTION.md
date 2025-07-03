# Contributing to Livcap

Thank you for your interest in contributing to Livcap! This document outlines our contribution guidelines and core principles that guide all development decisions.

## 🎯 Core Principles

Livcap is built around three fundamental principles that **ALL** contributions must align with:

### 1. Privacy First 🔒
- **Zero data collection**: No user data collection, analytics, or telemetry
- **No network communication**: All processing must remain local
- **No third-party services**: No external APIs or cloud dependencies
- **⚠️ Any code introducing data collection or network communication will be rejected**

### 2. Lightweight Performance 🚀
- **Minimal resource usage**: Keep CPU, memory, and battery consumption low
- **Efficient algorithms**: Prioritize performance over feature complexity
- **Native frameworks only**: Use Apple's native frameworks for optimal performance
- **⚠️ Features that significantly impact performance will be rejected**

### 3. Simple UI Design 🎨
- **Minimal interface**: Clean, distraction-free captioning display
- **Essential controls only**: Only include absolutely necessary UI elements
- **Consistent design**: Follow established UI patterns and styling
- **⚠️ Complex UI redesigns or excessive visual elements will be rejected**

## 📋 Pull Request Requirements

### Required PR Content
Every pull request **MUST** include:

1. **Feature Motivation**
   - Clear explanation of why this feature is needed
   - How it aligns with Livcap's core principles
   - User benefit description

2. **Code Changes Summary**
   - Simplified explanation of what was changed
   - Which files were modified and why
   - Architecture impact assessment

3. **AI Assistance Documentation**
   - How AI tools (Claude, ChatGPT, etc.) helped with the implementation
   - Which parts were AI-generated vs human-written
   - Verification steps taken for AI-generated code

4. **Demo/Showcase(optional)**
   - Screenshots or screen recordings of the feature in action
   - Before/after comparisons for improvements
   - Test results or performance metrics

### ⚠️ Important Notice
**Pull requests that don't follow these requirements will NOT be merged.** We reserve the right to refuse any PR that doesn't align with our principles or meet our standards.

## 🛠️ Development Guidelines

### Code Standards
- **Swift best practices**: Follow Swift API design guidelines
- **Documentation**: Include inline documentation for public APIs
- **Error handling**: Implement proper error handling and recovery
- **Testing**: Include unit tests for new functionality when possible

### Architecture Requirements(optional)
- **MVVM pattern**: Follow the established MVVM architecture
- **Dependency injection**: Use constructor injection for testability
- **AsyncStream**: Prefer AsyncStream for async operations
- **ObservableObject**: Use @Published properties for UI state


## 🚀 Getting Started

### Development Setup
1. **macOS Requirements**: macOS 14.4+ for system audio features
2. **Xcode**: Latest stable version
3. **Swift**: 5.9+
4. **Permissions**: Microphone access required for testing

### Before Contributing
1. **Read the code**: Understand the existing architecture 
2. **Check existing issues**: Avoid duplicate work
3. **Start small**: Begin with minor improvements or bug fixes
4. **Test thoroughly**: Ensure your changes don't break existing functionality

### Development Process
1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes**: Following our guidelines
4. **Test extensively**: Verify functionality and performance
5. **Submit a PR**: With all required documentation




## 🚫 What We Don't Accept

### Rejected Contributions
- **Analytics or tracking**: Any form of user data collection
- **Network features**: Cloud sync, remote processing, online features
- **Complex UI**: Dashboards, settings panels, visual customization
- **Performance-heavy features**: Real-time effects, complex processing

### Common Rejections
- **Feature creep**: Adding too many options or configurations
- **UI complexity**: Making the interface more complex
- **Performance regression**: Slowing down the core functionality
- **Privacy concerns**: Any potential data leakage or collection

## 🤝 Community

### Communication
- **GitHub Issues**: For bug reports and feature discussions
- **Pull Requests**: For code contributions
- **Discussions**: For general questions and ideas

### Code of Conduct
- **Respectful communication**: Professional and constructive feedback
- **Constructive criticism**: Focus on code and ideas, not individuals
- **Collaborative spirit**: Help others learn and improve

---

**By contributing to Livcap, you agree to these guidelines and principles. We appreciate your interest in making Livcap better while maintaining our core values of privacy, performance, and simplicity.**

*Last Updated: July 2025*