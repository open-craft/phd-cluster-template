# Documentation

This directory contains the documentation for the Launchpad (Launchpad) cluster template, built with [MkDocs](https://www.mkdocs.org/) and the [Material theme](https://squidfunk.github.io/mkdocs-material/).

## Prerequisites

- Python 3.12 or higher
- [`uv`](https://github.com/astral-sh/uv) package manager

## Installation

Install the documentation dependencies using `uv`:

```bash
# From the repository root
uv venv
uv pip install -r docs/requirements.txt
```

This creates a virtual environment (`.venv`) at the repository root and installs the MkDocs dependencies, making them available to `uv run` commands.

## Development

All MkDocs commands should be run from the repository root (where `mkdocs.yaml` is located):

### Running the Development Server

Start the MkDocs development server to preview the documentation locally:

```bash
# From the repository root
uv run mkdocs serve
```

The documentation will be available at `http://127.0.0.1:8000/`. The server will automatically reload when you make changes to the documentation files.

### Building the Documentation

To build the documentation as static HTML files:

```bash
# From the repository root
uv run mkdocs build
```

The built files will be output to the `public/` directory (as specified in `mkdocs.yaml`).

### Deploying to GitHub Pages

To deploy the documentation to GitHub Pages:

```bash
# From the repository root
uv run mkdocs gh-deploy --force
```

This command builds the documentation and pushes it to the `gh-pages` branch of the repository.

## Project Structure

```
.
├── mkdocs.yaml            # MkDocs configuration (at repository root)
└── docs/
    ├── css/               # Custom CSS styles
    ├── images/            # Images and assets
    ├── theme_overrides/   # Custom theme overrides
    ├── index.md           # Homepage
    ├── requirements.txt   # Python dependencies
    └── README.md          # This file
```

## Configuration

The MkDocs configuration is defined in `mkdocs.yaml` at the repository root. Key features include:

- **Material theme** with custom branding
- **Mermaid diagrams** support
- **Glightbox** for image galleries
- **Search** functionality
- **Code highlighting** with Pygments
- **Admonitions** and tabs for enhanced content presentation

## Contributing

When adding or modifying documentation:

1. Edit the Markdown files in the `docs/` directory
2. Use `uv run mkdocs serve` to preview changes locally
3. Ensure the documentation builds successfully with `uv run mkdocs build`
4. Commit your changes and open a pull request

For more information about MkDocs, see the [official documentation](https://www.mkdocs.org/).
