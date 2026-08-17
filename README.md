# Alex's profile

## Usage

This will first determine if its being run on MacOs or Linux, pull the latest version and then run the required script depending on OS
Run:

```bash
$ cd ~
$ git clone https://github.com/alexwilliams0712/profile.git
$ source setup_entry.sh
```

Setup output is stored privately at
`${XDG_STATE_HOME:-$HOME/.local/state}/profile/setup/latest.log`. Override the
directory with an absolute `PROFILE_SETUP_LOG_DIR`. The setup shows completed
steps with a Rich-style progress bar generated from the active platform setup
functions.
