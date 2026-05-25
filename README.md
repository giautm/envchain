# envchain

Set environment variables from macOS Keychain or Linux Secret Service. A Swift reimplementation of [sorah/envchain](https://github.com/sorah/envchain).

CLI-compatible with the original `sorah/envchain` — works as a drop-in replacement.

## Installation

### From Source

Requires Swift 6.0+.

```
make
sudo make install
```

### Linux Dependencies

On Linux, envchain uses libsecret (GNOME Keyring / Secret Service):

```
sudo apt install libsecret-1-dev
```

## Usage

### Save variables

```
envchain set NAMESPACE ENV [ENV ..]
```

You will be prompted to enter values:

```
$ envchain set aws AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
aws.AWS_ACCESS_KEY_ID: my-access-key
aws.AWS_SECRET_ACCESS_KEY: secret
```

### Execute commands with variables

```
$ envchain exec aws env | grep AWS_
AWS_ACCESS_KEY_ID=my-access-key
AWS_SECRET_ACCESS_KEY=secret

$ envchain exec aws s3cmd ls
```

Since `exec` is the default subcommand, you can omit it:

```
$ envchain aws s3cmd ls
```

Multiple namespaces separated by commas:

```
$ envchain aws,hubot env | grep 'AWS_\|HUBOT_'
```

### List namespaces

```
$ envchain list
aws
hubot
```

### List keys in a namespace

```
$ envchain list myns
KEY_A
KEY_B
```

### Show values

```
$ envchain list -v myns
KEY_A=value_a
KEY_B=value_b
```

### Remove variables

```
$ envchain unset aws AWS_SECRET_ACCESS_KEY
```

### Print as JSON

```
$ envchain json aws
{"AWS_ACCESS_KEY_ID":"my-access-key","AWS_SECRET_ACCESS_KEY":"secret"}
```

### AWS credential_process

Use envchain as an AWS SDK [credential_process](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sourcing-external.html) provider:

```
$ envchain aws-credential aws
{"AccessKeyId":"my-access-key","SecretAccessKey":"secret","Version":1}
```

In `~/.aws/config`:

```ini
[profile myprofile]
credential_process = envchain aws-credential aws
```

Supported keychain keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (optional), `AWS_CREDENTIAL_EXPIRATION` (optional).

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `set` | Add keychain items for a namespace |
| `list` | List namespaces or keys |
| `unset` | Remove keychain items |
| `json` | Print all values in a namespace as JSON |
| `aws-credential` | Output AWS credential_process JSON format |
| `exec` (default) | Execute a command with environment variables |

### Options (for `set`)

| Flag | Description |
|------|-------------|
| `-n`, `--noecho` | Do not echo input when prompting |
| `-p`, `--require-passphrase` | Require authentication to access the item |
| `-P`, `--no-require-passphrase` | Do not require authentication |

### Alternative flag syntax

The original `sorah/envchain` flag-style syntax is also supported:

```
envchain --set aws KEY        # same as: envchain set aws KEY
envchain --list               # same as: envchain list
envchain --unset aws KEY      # same as: envchain unset aws KEY
envchain --json aws           # same as: envchain json aws
envchain --aws-credential aws # same as: envchain aws-credential aws
```

## How it works

Secrets are stored in the macOS Keychain (or Linux Secret Service via libsecret) as generic passwords with service name `envchain-NAMESPACE`. When executing a command, envchain sets the stored key-value pairs as environment variables then replaces itself with the target process via `execvp`.

## Development

```
# Build (debug)
make build

# Build (release)
make

# Run tests (Linux — requires dbus and gnome-keyring)
make test
```

## License

MIT
