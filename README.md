# Runcode

## Default Mappings

Mappings are fully customizable.

| Mappings       | Action                                                    |
| -------------- | --------------------------------------------------------- |
| `<C-x>`        | Run/halt/resume execution of current buffer               |
| `<C-z>`        | Close the output buffer and resume with `<C-x>`           |  


### Developing

#### Test with custom log level
RUNCODE_LOG_LEVEL=debug nvim script.py

#### Watch logs
tail -f .cache/nvim/runcode.log
