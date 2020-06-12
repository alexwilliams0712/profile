# Alex's Mac zsh_profile

If anybody has any suggestions, please feel free to raise a PR.

## Usage

Open Terminal
Run:

```zsh
cd ~
git clone https://github.com/alexwilliams0712/profile.git
source profile/tools/setup.zsh
```

## Notes

### Directories

This will set up a CODE directory within your home folder as well as set up OhMyZSH and Pure. Within CODE is a folder for all git repos, and another for jupyter notebooks (called sandbox). This also creates a virtualenv for jupyter and pip installs: jupyter, voila, pandas, requests, matplotlib & nb_black.

### Apps

This will also brew install the following apps:

* cleanmymac
* dropbox
* franz
* google-chrome
* istat-menus
* iterm2
* julia
* microsoft-excel
* sublime-text
* visual-studio-code
* vlc
* vuze
* webex-meetings

If you have any of these installed without using HomeBrew, setup will fail. If you installed any of them using HomeBrew, they will be updated.

My Visual Studio Code settings json is also copied to:

```~/Library/application\ support/Code/User/settings.json```

which is where VS Code picks it up from.

### Git

This will create a git config for the user, who will need to enter the email and username used for git to populate it.

### ToDo

* Install a list of VS Code extensions (hopefully done)
* Fix pre-commit hooks so they work for Mac (currently copied from Windows).
* Create virtualenv for Black doesnt work currently.
* Pure to show virtualenvs (need to do this before switch it on).
