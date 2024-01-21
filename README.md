# runcode

## Default Mappings

Mappings are fully customizable.

| Mappings       | Action                                                    |
| -------------- | --------------------------------------------------------- |
| `<C-x>`        | Run/halt/resume execution of current buffer               |
| `<C-z>`        | Close the output buffer. Resume with <C-x>                |  


### Developing

#### set log level
RUNCODE_LOG_LEVEL=debug nvim script.py

#### watch logs
tail -f .cache/nvim/runcode.log
