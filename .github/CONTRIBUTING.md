# Contributing

Thanks for considering contributing to Edmund :)

## Getting started

There are several ways to contribute: 
1. Find something on the [backlog](https://trello.com/b/vw2TveNI), 
2. Create a new extension or improve an existing one, or
3. Add something brand new. 

Before you contribute, though make sure to 

1. Check if your idea aligns with Edmund's design philosophy (below), 
2. Check the [Trello board](https://trello.com/b/vw2TveNI), Issues, and Pull Requests to see if someone has already done something, and 
3. If your planned change is big, create a feature-request issue and note that you're actively working on it
    - Something like "[Incoming PR]" or "[PR WIP]" in the title would do

Not every PR will be merged, but at least at this point I can guarantee every PR will be responded to :D

## Philosophy

A partial repetition of the README pitch with more technical details: 

- **Native inside-out**
  - Edmund's core must be 100% Swift
    - The WebKit reader is only exception
  - Design decisions should follow Apple philosophy and macOS conventions where possible
    - E.g. "Less is more", intuitive interface
    - E.g. Prefer Application Support/ over external folders. 
- **Modular design with minimal core**
  - Edmund will ship editor + reader + essential functionalities only
  - Develop and use extensions for power features and fine-grained customization
    - Extensions are based on JSCore for compatibility with existing web-based tools
    - We are deliberately avoiding `.bundles` for now. That might change.
- **Modern, lightweight solutions over legacy solutions**
  - E.g. Shiki over Highlighter.js. Both great projects!
- **Accessibility and international support**
  - Coming soon!

## References

- `docs/` for an overview of architecture. (Sorry they're completely AI generated. I'll rewrite them before v1)
- Backlog, work-in-progress, and roadmap are all managed on [this Trello board](https://trello.com/b/vw2TveNI)
- Apple Notes, Xcode, and CotEditor
- List of extensions (coming soon)


