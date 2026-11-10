# Oh My Pi — Docker with Intelligence
Fork was created to add support for the Go language server (gopls) to make use of Oh My Pi's Code Intelligence feature. I intend to use this container for projects written in different languages, hence I'll be patching in support for different language servers into the harness as time goes by. 

The original author of the fork's origin is 19WAS85 and their code can be found here: [omp-docker](https://github.com/19WAS85/omp-docker). He provided a very solid foundation for me to extend and deserves all the kudos.

Docker harness for [Oh My Pi](https://github.com/can1357/oh-my-pi), the AI coding agent. Packages the full OMP environment — Bun, Python, ripgrep, LSP, DAP, 32 built-in tools — inside a container image. You work on your local files; OMP runs in Docker.

## Install

```sh
git clone https://github.com/19WAS85/omp-docker.git
cd omp-docker
make install
```

This builds the container image and creates wrapper scripts in `~/.local/bin`. Ensure `~/.local/bin` is on your `PATH`.

## Configuration

Edit `.env.default.properties` to customize settings, or set environment variables before running `make`. For secrets (API keys, tokens), create a local `.env.properties` file (gitignored).

| Variable | Default | Description |
|---|---|---|
| `WORKSPACE_DIR` | `.` | Host directory to mount at `/work` |
| `OMP_STATE_DIR` | `$HOME/.omp` | Persistent agent state directory |
| `SSH_DIR` | `$HOME/.ssh` | Host SSH directory (mounted read-only for commit signing) |
| `GIT_SIGNING_KEY` | `/root/.ssh/id_ed25519` | SSH key path for commit signing |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` | Ollama API endpoint reachable from the container |
| `RESOURCE_CPUS` | `2.0` | CPU limit |
| `RESOURCE_MEMORY` | `4g` | Memory limit |

OMP includes a built-in Ollama provider and discovers available models from the configured endpoint. Start Ollama on the host, then select an `ollama/<model>` model in OMP. Override `OLLAMA_BASE_URL` in `.env.properties` or your environment if Ollama is hosted elsewhere. On Linux, Ollama must listen on an address reachable from Docker (for example, set its `OLLAMA_HOST` to `0.0.0.0:11434`); `host.docker.internal` may also need a host-gateway entry depending on your Docker setup.

## CLI Commands

Once installed, three commands are available from anywhere:

### `omp-docker [args]`
Run the OMP agent with the current directory mounted at `/work`. All arguments are forwarded to the agent. Set `WORKSPACE_DIR` to override the directory for a particular run.

```sh
omp-docker                          # start agent interactively
omp-docker "fix the race condition in src/worker.py"
omp-docker --help
WORKSPACE_DIR=/path/to/project omp-docker
```

Your working directory is mounted at `/work` inside the container. `~/.omp` state persists across sessions; runtime sockets under `/root/.omp/run` use container-local temporary storage.

### `omp-docker-build [args]`

Rebuild the container image. Use after editing the `Dockerfile` or `compose.yaml`. Extra arguments are forwarded to `docker compose build`.

```sh
omp-docker-build                    # full rebuild
omp-docker-build --no-cache         # ignore build cache
```

### `omp-docker-update`

Rebuild the image from the update stage with cache busting, so OMP and its dependencies are refreshed without rebuilding system packages from scratch.

```sh
omp-docker-update                   # pull latest OMP packages
```

## Direct Makefile Usage

```sh
make docker          # build + run interactively (default)
make docker.build    # build image only
make docker.run      # run interactively
make docker.run.d    # run detached
make docker.stop     # stop containers
make docker.clean    # remove all project images
make docker.update   # rebuild from update stage (cache-busting)
make docker.ls       # list project images
make uninstall       # remove CLI wrapper scripts
make help            # show all available commands
```

## Adding OMP Plugins and Extensions

Run plugin management commands through `omp-docker` so they use the same persistent `~/.omp` state as the container. The host `omp` command may use a different state directory and leave marketplace paths that the container cannot read.

### Install from a marketplace

Add the marketplace once, discover its plugins, then install the selected plugin using its `plugin-name@marketplace-name` ID:

```sh
omp-docker plugin marketplace add anthropics/claude-plugins-official
omp-docker plugin discover claude-plugins-official
omp-docker plugin install frontend-design@claude-plugins-official
```

For example, to add the Go skills collection from `samber/cc`:

```sh
omp-docker plugin marketplace add samber/cc
omp-docker plugin discover samber
omp-docker plugin install cc-skills-golang@samber
```

Marketplace management commands:

```sh
omp-docker plugin marketplace list
omp-docker plugin marketplace update samber
omp-docker plugin list
omp-docker plugin uninstall cc-skills-golang@samber
```

Updating a marketplace refreshes its catalog; it does not upgrade installed plugins. Use `omp-docker plugin upgrade <plugin-name@marketplace-name>` to upgrade an installed marketplace plugin.

To check marketplace installs, use `omp-docker plugin list` or `/marketplace installed` inside an OMP session. `/skills installed` reports skills installed through OMP's separate skill registry; it does not list skills that come from marketplace plugins. Marketplace plugin skills are discovered by OMP at session startup. Run `/reload-plugins` or restart OMP after installing one, and invoke a skill explicitly with `/skill:<plugin-name>/<skill-name>` when needed. For example, the Go skills collection can be invoked with `/skill:cc-skills-golang/golang-security`.

### Install an extension package

OMP can install extension packages from a package registry or a Git repository:

```sh
omp-docker plugin install <package-name>
omp-docker plugin install github:<owner>/<repository>
```

To use an extension checked out locally, link its directory. Paths must be visible inside the container; a directory in the mounted working tree is under `/work`:

```sh
omp-docker plugin link /work/path/to/extension
```

User-scoped installs are the default and are available across projects. Marketplace plugins can also be installed for the current project with `--scope project`:

```sh
omp-docker plugin install --scope project <plugin-name@marketplace-name>
```

After managing plugins from inside an active OMP session, run `/reload-plugins` to refresh skills, slash commands, task agents, and MCP servers. Restart the session to load newly installed tools, hooks, or extension modules. If installation was performed with `omp-docker` from the shell, start a new `omp-docker` session to load the changes.

## What's Inside

- **Bun** runtime with `@oh-my-pi/pi-coding-agent` and `@oh-my-pi/pi-natives`
- **Python 3** with ipykernel at `/opt/omp-venv`
- **ripgrep**, **fd-find**, **build-essential**, **git**, **iptables**

To add packages, edit the `Dockerfile` and rebuild with `omp-docker-build`.

## Architecture

```
omp-docker [args]
  └─ make docker.run
      └─ docker compose run --rm omp
          └─ entrypoint.sh
              └─ exec omp [args]
```

`omp update` runs at image build time (`RUN omp update` in the Dockerfile), not at container startup.

| File | Purpose |
|---|---|
| `Makefile` | Primary CLI interface |
| `Dockerfile` | Container image (oven/bun:1.3). `omp update` runs at build time. |
| `compose.yaml` | Service config: mounts, env, capabilities, network, resource limits |
| `entrypoint.sh` | Copies SSH keys with correct perms, dispatches commands via `exec` |
| `.env.default.properties` | Committed default configuration |
| `.dockerignore` | Excludes .git, docs, markdown from build context |

## Security

- **Resource limits**: CPU and memory capped via `deploy.resources.limits`
- **Network isolation**: Custom bridge network with controlled egress
- **Capabilities**: `NET_ADMIN` and `NET_RAW` are required for iptables-based egress control (agent network sandboxing)
- **Credential isolation**: Git identity via `~/.gitconfig` (mounted read-only, auto-detected); `~/.ssh` mounted read-only for commit signing
- **Cache persistence**: Named volumes for pip/npm caches

## Contributing

1. Fork and create a feature branch
2. Make changes to the Dockerfile, Makefile, or compose config
3. Test with `make docker.run echo "ok"`
4. Submit a pull request
