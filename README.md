# Shipment Tracker
[![Circle CI](https://circleci.com/gh/FundingCircle/shipment_tracker.svg?style=shield)](https://circleci.com/gh/FundingCircle/shipment_tracker)

![](http://i.imgur.com/VkjlJmj.jpg)

Tracks shipment of software versions for audit purposes.

The app has various "audit endpoints" to receive events,
such as deploys, builds, ticket creations, etc.

We use an append-only store, nothing in the DB is ever modified or deleted.
Event sourcing is used to replay each event allowing us to reconstruct the state
of the system at any point in time.

## Getting Started

Install the gems and set up the database.

```
bundle install
bundle exec rake db:setup
```

Set up Git hooks, for running tests and linters before pushing to master.

```
rake git:setup_hooks
```

You can use Guard during development to run rspec, cucumber, and rubocop when it detects any changes.

```
bundle exec guard
```

### Enabling access to repositories via SSH

Ensure that `libssh2` is installed and the `rugged` gem is reinstalled. On OSX:

```
brew install libssh2
gem pristine rugged
```

When booting server, set Environment variables `SSH_USER`, `SSH_PUBLIC_KEY` and `SSH_PRIVATE_KEY`:

```
SSH_USER=git \
SSH_PUBLIC_KEY='ssh-rsa AAAXYZ' \
SSH_PRIVATE_KEY='-----BEGIN RSA PRIVATE KEY-----
abcdefghijklmnopqrstuvwxyz
-----END RSA PRIVATE KEY-----' \
rails s
```

You can also use Foreman to start the server.

## License

Copyright © 2015 Funding Circle Ltd.

Distributed under the BSD 3-Clause License.
