# Contributing to PSNutanixOps

Thank you for your interest in contributing! We appreciate your help in making this project better.

## Quick Start

1. **Fork and clone** the repository
2. **Create a branch**: `git checkout -b feature/your-feature`
3. **Make your changes**
4. **Run tests**: `Invoke-Build Test`
5. **Commit with semver keyword**: `git commit -m "Add feature +semver: minor"`
6. **Push and create a Pull Request**

## What We Need

### Before You Start

- Check existing issues and PRs to avoid duplicates
- For major changes, open an issue first to discuss

### Code Requirements

✅ **Must have:**

- Tests pass (`Invoke-Build Test`)
- PSScriptAnalyzer passes (automatic in CI)
- Tests for new functions (`.Tests.ps1` files)

✅ **Good to have:**

- Comment-based help for public functions
- Clear commit messages
- Updated documentation if needed

### File Locations

- Public functions → `src/Public/Verb-Noun.ps1`
- Private functions → `src/Private/`
- Tests → Same location as function with `.Tests.ps1` suffix

## Commit Messages

Use these keywords to control versioning:

```bash
git commit -m "Add new feature +semver: minor"       # New feature
git commit -m "Fix bug +semver: patch"               # Bug fix  
git commit -m "Breaking change +semver: major"       # Breaking change
git commit -m "Update docs +semver: none"            # No version bump
```

## Need Help?

- 📖 See [Getting Started](docs/getting-started.md) for setup
- 📖 See [Development Guide](docs/development.md) for details
- 💬 Open an issue for questions

## Code of Conduct

Be respectful and collaborative. That's it.

---

**Thank you for contributing!** 🎉
