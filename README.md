# envchain

Set environment variables from macOS Keychain. A Swift reimplementation of [sorah/envchain](https://github.com/sorah/envchain).

## Installation

### From Source

```
make
sudo make install
```

## Usage

### Save variables

```
envchain --set NAMESPACE ENV [ENV ..]
```

You will be prompted to enter values:

```
$ envchain --set aws AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
aws.AWS_ACCESS_KEY_ID: my-access-key
aws.AWS_SECRET_ACCESS_KEY: secret
```

### Execute commands with variables

```
$ envchain aws env | grep AWS_
AWS_ACCESS_KEY_ID=my-access-key
AWS_SECRET_ACCESS_KEY=secret

$ envchain aws s3cmd ls
```

Multiple namespaces separated by commas:

```
$ envchain aws,hubot env | grep 'AWS_\|HUBOT_'
```

### List namespaces

```
$ envchain --list
aws
hubot
```

### List keys in a namespace

```
$ envchain --list myns
KEY_A
KEY_B
```

### Show values

```
$ envchain --list -v myns
KEY_A=value_a
KEY_B=value_b
```

### Remove variables

```
$ envchain --unset aws AWS_SECRET_ACCESS_KEY
```

### Print as JSON

```
$ envchain --json aws
{"AWS_ACCESS_KEY_ID":"my-access-key","AWS_SECRET_ACCESS_KEY":"secret"}
```

### AWS credential_process

Use envchain as an AWS SDK [credential_process](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sourcing-external.html) provider:

```
$ envchain --aws-credential aws
{"AccessKeyId":"my-access-key","SecretAccessKey":"secret","Version":1}
```

In `~/.aws/config`:

```ini
[profile myprofile]
credential_process = envchain --aws-credential aws
```

Supported keychain keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (optional), `AWS_CREDENTIAL_EXPIRATION` (optional).

### Options

| Flag | Description |
|------|-------------|
| `--set`, `-s` | Add keychain items for a namespace |
| `--list`, `-l` | List namespaces or keys |
| `--json` | Print all values in a namespace as JSON |
| `--aws-credential` | Output AWS credential_process JSON format |
| `--unset` | Remove keychain items |
| `--noecho`, `-n` | Do not echo input when prompting |
| `--require-passphrase`, `-p` | Require authentication to access the item |
| `--no-require-passphrase`, `-P` | Do not require authentication |

## How it works

Secrets are stored in the macOS Keychain as generic passwords with service name `envchain-NAMESPACE`. When executing a command, envchain sets the stored key-value pairs as environment variables then replaces itself with the target process via `execvp`.

## License

MIT
