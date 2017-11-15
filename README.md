# Solavirum.Logging.ELK.Elastalert.Config

## What is this?

This repository contains a deployable package that can be used to deploy Elastalert configuration and rules to an EC2 instance that is running Elastalert via a docker container.

## Quick Start - Adding a new rule

> First things first. You are going to need a Linux machine with Docker installed. This has the added benfit of letting you develop/test on the same image that is used in our actual environments.

You are probably here because you want to add a new Elastalert rule. A rule is just a yaml file structured in a certain way. You can read up about the different types of rules Elatalert supports in their [documentation](http://elastalert.readthedocs.io/en/latest/ruletypes.html). Once you are across how to write your rule, here is how you add it to this project:

1. Ensure you have a local (non-source controlled) file named: `src/config/substitutions/Sensitive.Local.conf`. In this file assign a valid Hipchat API token to a variable called `HIPCHAT_TOKEN`.
1. Add your rule under `src/rules`.
1. [Optional] If your rule requires substitutions, i.e. values that you want to vary according to environment, you will need to do the following:

    1. Use a placeholer in your rule file. The convention is to surround some key with '@@', e.g. @@MY_VAR@@.
    1. Add a default value into `src/config/substitutions/Default.conf`, e.g. `MY_VAR=5`. If you want specific values for different environments add them into the relevant enviroment based files, i.e. `src/config/substitutions/{CI|Staging|Production}.conf`.

    > Note that any sensitive information (such as passwords, api tokens etc) should be placed into `src/config/substitutions/Sensitive.Local.conf` for local development and read from Octopus variables when actually deployed. If you add new senesitive substitutions you will need to update `deploy.sh` to read the relevant Octopus variable. This will then end up in a file named `Sensitive.Octopus.conf`. Ensure the Octopus project has this variable set for all relevant environments.

1. [Optional] Add exclusions for the environments you don't wish your rule to run in to the relevant file under `src\config\rule_exclusions\rule_exclusions.[Environment].conf`. Normal file system patterns are supported e.g. `ci*` will exlude all rules starting with "ci".
    
1. Test your rule (assuming there are enough events in ELK to trigger it) by running `deploy.sh` from inside the `src` directory. This script can take the following command line options which are helpful for testing your new rule in a development environment:

    * `-r | --rule` - allows you to run for only rules matching this argument. Normal file system wilcards are supported, e.g. `./deploy.sh -r gateway*`
    * `-e | --environment` - allows you to target a certain environment. This drives the substitutions that will be made and is a quick way to see how your rule behaves when targetting a specific ELK environment. Supported values are CI, Staging, and Production.

1. Commit, Push, Done :)


## Troubleshooting

### It's not running at all...

Odds are you done screwed up your rule. I know I did. Thankfully, Elastalert has pretty good logs, which you can get at through Docker.

Here is a quick summary of some docker commands that will be helpful in troubleshooting.

* `docker ps` - will get you a list of the containers currently running. They will have interesting names.
* `docker logs -f {name|id}` - follows the logs from a particular container (`ctrl-c` will stop following).
* `docker exec -it {name|id} sh` - shells into the container.
* `docker top {name|id|}` - this will show you the processes running inside the container. One of them should be a python process running elastalert, e.g. `python -m elastalert.elastalert --config /opt/config/elastalert.yaml`

### It's running, but I'm not getting alerts (and I should be)

If the logs (and the output of `deploy.sh`) suggest that everything worked and Elastlaert is up and running but you are not seeing alerts come through you can check the Elastalert index in Elasticsearch. This is an index that Elastalert writes meta-data about it's runs and alert decisions to. You can find information about how to interpret the documents in this index [here](http://elastalert.readthedocs.io/en/latest/elastalert_status.html).

Each run of `deploy.sh` will result in a new and completely isolated directory at `src/runs/[timestamp]`. This directory will contain all config and rule files post-substitution so you can inspet them and ensure the right values are getting substituted into the right places. There will also be a `Variables.conf` in the run directory that will contain the values of all the variables that were resolved/used.

## How does it work?

There is a simple AWS CloudFormation stack (AutoScaling group + Launch configs) that launches EC2 instances with Docker pre-installed. These instances are registered as Octopus Deploy targets as part of the Launch Configuration. This environment is all automated and you can find the source for it [here](https://github.com/ToddBowles/Solavirum.Logging.ELK.Elastalert.Environment).

*This repository* allows a package to be built and deployed, via Octopus Deploy, to the instances mentioned above. The `src/deploy.sh` script is what Octopus will run on the instance (over SSH). At a high level the deploy script does the following:

1. Creates a new "run" directory at `src/runs/[timestamp]`. This is a way to keep an isolated set of configuration and rule files.
1. Resolve "substitutions". Substitutions are values that need to be replaced inside a configuration or rule file, usually with different values depending on the environment that is being deployed to. It does this by loading values from the following files:
    
    1. `/src/substitutions/Default.conf`
    1. `/src/substitutions/[Environment].conf` - where Environment is one of CI, Staging, or Production.
    1. `/src/substitutions/[Sensitive.[Local|Octopus].conf` - `Sensitive.Local.conf` is a file you can set up locally (but not check into source control) and `Sensitive.Octopus.Conf` is a file that will be dynamically created by `deploy.sh` and populated with values read from Ocotpus variables.

1. Copies the base files to the run directory, i.e. `src/config` to `src/runs/[timestamp]/config` and `src/rules` to `src/runs/[timestamp]/rules`.
1. Removes any rule files from `src/runs/[timestamp]/rules` that should not be applied for the current environment. This is driven by the entries in the relevant `src/config/rule_exclusions/rules_exclusions.[Environment].conf` file.
1. Performs the substitutions that were resolved in every file in `src/runs/[timestamp]` (recursively).
1. Stops and removes any existing Docker containers
1. Starts a new Docker container that runs Elastalert. This involes mapping volumes (to directories in the run directory), setting environment variables (most notably Elasticsearch hosts and ports), and defining which configuration files should be used to run Elastalert inside the container.

# Who is responsible for this terrible thing?
While the repo lives under the Github account of [Todd Bowles](https://github.com/ToddBowles) (mostly because he wrote a blog post about the subject, found [here](http://www.codeandcompost.com/post/we%E2%80%99re-finally-paying-attention,-part-3), the majority of the work was completed by [Brad Bow](https://github.com/beeleebow).