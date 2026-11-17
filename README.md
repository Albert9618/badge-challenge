# Batch Resolution Take-Home Challenge

Thanks for taking the time to do this! You'll fix an issue in a small Salesforce codebase on your own time. Then, in a 60-minute live session, you'll walk us through your work.

## Background

Our learning platform runs on Salesforce. Learners earn **certifications**, and each certification can have a public digital **badge** hosted on an external badging platform.

When a learner is deactivated, a nightly batch, `LearnerDeactivationBatch`, does two things:

1. Expires the learner's active certifications in Salesforce.
2. Tells the badging platform, so the learner's public badge also shows as expired.

In this repo, the badging platform is played by [Postman Echo](https://postman-echo.com), a public endpoint that echoes back whatever you send it.

## The incident

> **From the Support team:**
> Learners who were deactivated over the last few months still show **active** certifications in Salesforce, and their public badges still say **Active**. The nightly cleanup job runs every night and shows **Completed** in Apex Jobs. Nobody has received any error emails, and the test class passes.

In production, about **100,000** certifications are waiting to be expired.

## What we'd like you to do

### 1. Find the root cause
Work out why certifications aren't expiring and badges aren't updating, why the job still shows Completed, and why the tests didn't catch it. You'll explain this in the live session, so no write-up is needed.

### 2. Fix it
We're especially interested in how you use Salesforce's asynchronous processing tools, so the fix is more than a one-line change. Your fix should meet these requirements:

- **R1:** Active certifications belonging to deactivated learners are expired, and their badges are updated on the badging platform.
- **R2:** It works for the full seed data set (60 learners, 180 certifications, 120 badges) in a single run of the batch, and it would hold up at production volume.
- **R3:** When a run fails, someone can find out without reading debug logs. Keep it simple: an email alert is enough.
- **R4:** Badge updates run as their own asynchronous process, separate from expiring the certifications.
- **R5:** Make the tests trustworthy.
The existing test passes, but it didn't catch this bug. Fix the tests so they are more reliable.

You can change anything: classes, objects, fields, the batch's structure. No UI is needed.

## Ground rules

- **AI is welcome.** Use Claude, Copilot, ChatGPT, docs, search, whatever you use on the job. In the live session we'll ask you to explain your code and make a small change to it, so make sure you understand everything you submit.

## Setup (about 5 minutes)

You need the Salesforce CLI (`sf`), git, and a free personal [Developer Edition org](https://developer.salesforce.com/signup) with Dev Hub enabled (Setup → Dev Hub → Enable Dev Hub). 

```bash
./scripts/setup.sh
```

This creates a scratch org (it lasts 14 days), deploys the project, and loads the seed data. Open the org with `sf org open`.

### What's in the repo

| Path | What it is |
|---|---|
| `classes/LearnerDeactivationBatch.cls` | The nightly batch |
| `classes/BadgeClient.cls` | Sends status updates to the badging platform |
| `classes/LearnerDeactivationBatchTest.cls` | The existing test |
| `objects/Certification__c` | Certification: `User__c`, `Status__c`, `ExpirationDate__c`, `BadgeId__c` |
| `objects/Badge_Settings__mdt` | Badging platform endpoint |
| `scripts/apex/` | Run the batch, reset the data |
| `scripts/soql/` | Check recent async jobs and certification counts |

### Useful commands

```bash
sf apex run --file scripts/apex/run-batch.apex
```

```bash
sf data query --file scripts/soql/recent-async-jobs.soql
```

```bash
sf data query --file scripts/soql/cert-status.soql
```

```bash
sf apex run --file scripts/apex/reset-certs.apex
```

```bash
sf apex run test --class-names LearnerDeactivationBatchTest --result-format human --code-coverage
```

## Submitting

1. Push your work to a **private** GitHub repo and give access to the GitHub users listed in your invite.
2. Reply to your invite email with the link by the deadline.

## The live session (60 minutes)

Have your scratch org and dev environment open and ready to share. We'll ask you to:

1. Walk us through the root cause and your fix, and show it running on the seed data.
2. Answer questions about your code and the choices you made, including the alternatives you considered and how you used AI.
3. Make a small change to your code live. AI tools are fine here too.
4. Talk through a few "what if" scenarios.
