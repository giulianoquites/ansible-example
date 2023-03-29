# Automation Controller Export Documentation

## Description

This is documentation on how to use a the Automation Controller export commands in development. You can also look at the role as another method to export data.

This command allows exporting all available endpoints for Automation Controller for use in importing, templates, backups and many other uses.

## Installation

```console
pip3 install awxkit
```

## Basic command options

```console
awx export --conf.host https://localhost --conf.username admin --conf.password ******** --conf.insecure --help
```

```console
Export in Terminal:
awx export --conf.host https://localhost --conf.username admin --conf.password ******** --conf.insecure --job_templates 
Expoer in file:
awx export --conf.host https://localhost --conf.username admin --conf.password "*****" --conf.insecure --organizations    > organizations.json   
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --users    > users.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --teams    > teams.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --credential_types    > credential_types.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --credentials    > credentials.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --notification_templates    > notification_templates.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --projects    > projects.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --inventory    > inventory.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --inventory_sources    > inventory_sources.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --job_templates    > job_templates.json
awx export --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure --workflow_job_templates    > workflow_job_templates.json
```

```console
Import:
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < organizations.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < users.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < teams.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < credential_types.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < credentials.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < notification_templates.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < projects.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < inventory.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < inventory_sources.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < job_templates.json
awx import --conf.host https://localshot --conf.username admin --conf.password "*****" --conf.insecure < workflow_job_templates.json

```


## Available options for this command

|Option|
|:---:|
|users|
|organizations|
|teams|
|credential_types|
|credentials|
|notification_templates|
|projects|
|inventory|
|inventory_sources|
|job_templates|
|workflow_job_templates|

